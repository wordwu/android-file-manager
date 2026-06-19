import Foundation
/// ADB 服务单例——所有 Android 设备通信的统一入口。
///
/// **线程安全约定**:
/// - `@unchecked Sendable` 绕过了编译器的 Sendable 检查，原因: `OperationQueue`、
///   `NSLock`、`Process?` 均非 Sendable 类型。
/// - 所有可变状态通过以下机制保护：
///   - `transferLock (NSLock)`: 保护 `currentTransferProcess` 的读写
///   - `OperationQueue.maxConcurrentOperationCount = 1`: 串行化 adb 命令执行
///   - `mockShell`: 仅测试使用，通过 `setMockShell()` 在 test setUp 中设置
/// - 新增属性必须遵循以上约定，否则需改用 actor 隔离。
@MainActor
final class ADBService: @unchecked Sendable {
    static let shared = ADBService()

    /// 调试用 mock shell，注入后 run() 不再启动真实 adb 进程
    var mockShell: (([String], TimeInterval) throws -> String)?

    let adbPath: String
    let fileManager = FileManager.default
    let operationQueue = OperationQueue()

    private init() {
        operationQueue.maxConcurrentOperationCount = 1

        // 1. App 内嵌 adb（优先）——先清隔离属性再检测
        if let bundleAdb = Bundle.main.path(forResource: "adb", ofType: nil) {
            // 清除 macOS 隔离标记（通过微信/AirDrop 传来会带 quarantine）
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-d", "com.apple.quarantine", bundleAdb]
            xattr.standardOutput = FileHandle.nullDevice
            xattr.standardError = FileHandle.nullDevice
            do {
                try xattr.run()
                xattr.waitUntilExit()
            } catch {
                androidFMLog("[ADBService] init: xattr run failed: \(error)")
            }
            if xattr.terminationStatus != 0 {
                androidFMLog("[ADBService] init: xattr quarantine removal failed (exit \(xattr.terminationStatus))")
            }

            if fileManager.isExecutableFile(atPath: bundleAdb) {
                self.adbPath = bundleAdb
                adbAvailable = true
                androidFMLog("[ADBService] init: using bundled adb")
                return
            }
        }

        // 2. ~/android-sdk/platform-tools/adb
        let androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"]
            ?? "\(NSHomeDirectory())/android-sdk"
        let sdkAdb = "\(androidHome)/platform-tools/adb"
        if fileManager.isExecutableFile(atPath: sdkAdb) {
            self.adbPath = sdkAdb
            adbAvailable = true
            androidFMLog("[ADBService] init: using sdk adb at \(adbPath)")
            return
        }

        // 3. 系统 PATH
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["adb"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            androidFMLog("[ADBService] init: which adb run failed: \(error)")
        }
        if process.terminationStatus != 0 {
            androidFMLog("[ADBService] init: which adb failed (exit \(process.terminationStatus))")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let sysAdb = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !sysAdb.isEmpty && process.terminationStatus == 0 {
            self.adbPath = sysAdb
            adbAvailable = true
            androidFMLog("[ADBService] init: using system adb at \(adbPath)")
            return
        }

        self.adbPath = sdkAdb
        adbAvailable = false
        androidFMLog("[ADBService] init: adb NOT FOUND")
    }

    var adbAvailable = false
    var isAdbAvailable: Bool { adbAvailable }

    // MARK: - Shell 转义工具
    
    /// 转义 shell 路径参数：反斜杠、美元符、双引号、反引号、感叹号
    func shellEscape(_ path: String) -> String {
        return path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "!", with: "\\!")
    }
    
    func shellQuote(_ s: String) -> String {
        return "'\(s.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
    // MARK: - 取消传输
    var currentTransferProcess: Process?
    let transferLock = NSLock()
    private static let transferProgressPattern = try! NSRegularExpression(pattern: #"Transferring:\s+(\d+)/(\d+)"#)
    func cancelCurrentTransfer() {
        transferLock.lock()
        if let proc = currentTransferProcess, proc.isRunning {
            (proc.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            kill(proc.processIdentifier, SIGKILL)
            currentTransferProcess = nil
        }
        transferLock.unlock()
    }

    // MARK: - 底层 Process 执行
    func run(_ arguments: [String], timeout: TimeInterval = 30, retryOnTimeout: Bool = false) throws -> String {
        if let mock = mockShell { return try mock(arguments, timeout) }
        guard adbAvailable else {
            throw ADBError.adbNotInstalled("adb 加载失败，请重新下载 App")
        }

        let maxRetries = retryOnTimeout ? 2 : 0

        for attempt in 0...maxRetries {
            if attempt > 0 {
                let delay = Double(attempt)
                androidFMLog("[ADBService] run retry \(attempt)/\(maxRetries) after \(delay)s delay")
                let semaphore = DispatchSemaphore(value: 0)
                _ = semaphore.wait(timeout: .now() + delay)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: adbPath)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            var environment = ProcessInfo.processInfo.environment
            environment["LC_ALL"] = "en_US.UTF-8"
            process.environment = environment

            let sem = DispatchSemaphore(value: 0)
            let exitBox = ExitCodeBox()
            process.terminationHandler = { proc in
                exitBox.value = proc.terminationStatus
                sem.signal()
            }

            try process.run()

            let deadline: DispatchTimeoutResult
            if timeout > 0 {
                deadline = sem.wait(timeout: .now() + timeout)
            } else {
                sem.wait()
                deadline = .success
            }

            guard deadline == .success else {
                process.terminate()
                _ = sem.wait(timeout: .now() + 3) // 给进程 3s 清理
                if retryOnTimeout && attempt < maxRetries {
                    androidFMLog("[ADBService] 命令超时，将重试 (\(attempt+1)/\(maxRetries))")
                    continue
                }
                throw ADBError.commandFailed(exitCode: -1, stderr: "命令超时 (\(timeout)s)")
            }

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: stdoutData, encoding: .utf8) ?? ""

            guard exitBox.value == 0 else {
                // 仅对 adb 连接临时性错误重试（255=连接丢失, 137=SIGKILL, 143=SIGTERM）
                let transientCodes: Set<Int32> = [255, 137, 143]
                if retryOnTimeout && attempt < maxRetries && transientCodes.contains(exitBox.value) {
                    let err = String(data: stderrData, encoding: .utf8) ?? ""
                    androidFMLog("[ADBService] 临时性错误(\(exitBox.value))，重试 (\(attempt+1)/\(maxRetries)): \(err)")
                    continue
                }
                let err = String(data: stderrData, encoding: .utf8) ?? ""
                throw ADBError.commandFailed(exitCode: exitBox.value, stderr: err)
            }

            return output
        }

        throw ADBError.commandFailed(exitCode: -1, stderr: "重试耗尽")
    }

    /// 本地命令执行（不经过 adb），用于 aapt 等本地工具
    func runLocal(_ executable: String, arguments: [String], timeout: TimeInterval = 30) throws -> String {
        if let mock = mockShell { return try mock([executable] + arguments, timeout) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "en_US.UTF-8"
        process.environment = environment

        let sem = DispatchSemaphore(value: 0)
        let exitBox = ExitCodeBox()
        process.terminationHandler = { proc in
            exitBox.value = proc.terminationStatus
            sem.signal()
        }

        try process.run()

        let deadline: DispatchTimeoutResult
        if timeout > 0 {
            deadline = sem.wait(timeout: .now() + timeout)
        } else {
            sem.wait()
            deadline = .success
        }

        guard deadline == .success else {
            process.terminate()
            _ = sem.wait(timeout: .now() + 3)
            throw ADBError.commandFailed(exitCode: -1, stderr: "本地命令超时 (\(timeout)s)")
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: stdoutData, encoding: .utf8) ?? ""

        guard exitBox.value == 0 else {
            let err = String(data: stderrData, encoding: .utf8) ?? ""
            throw ADBError.commandFailed(exitCode: exitBox.value, stderr: err)
        }

        return output
    }

    /// 带进度跟踪的命令（push/pull）
    func runWithProgress(_ arguments: [String], totalBytes: Int64,
                                 progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operationQueue.addOperation {
                let process = Process()
                self.transferLock.lock()
                self.currentTransferProcess = process
                self.transferLock.unlock()
                defer {
                    self.transferLock.lock()
                    if self.currentTransferProcess === process {
                        self.currentTransferProcess = nil
                    }
                    self.transferLock.unlock()
                }
                process.executableURL = URL(fileURLWithPath: self.adbPath)
                process.arguments = arguments

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                var environment = ProcessInfo.processInfo.environment
                environment["LC_ALL"] = "en_US.UTF-8"
                process.environment = environment

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }

                    // 解析 "Transferring: 1425408/8452096 (16%)"
                    if let match = Self.transferProgressPattern.firstMatch(in: line,
                                                     range: NSRange(line.startIndex..., in: line)),
                       let range1 = Range(match.range(at: 1), in: line),
                       let range2 = Range(match.range(at: 2), in: line),
                       let current = Int64(line[range1]),
                       let total = Int64(line[range2]) {
                        progress(current, total)
                    }
                }
                defer { stdoutPipe.fileHandleForReading.readabilityHandler = nil }

                do {
                    try process.run()

                    // 超时看门狗：300s 后发 SIGKILL，防止传输卡死阻塞整个串行队列
                    let pid = process.processIdentifier
                    let watchdog = DispatchWorkItem {
                        kill(pid, SIGKILL)
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + C.adbPushPullTimeout, execute: watchdog)
                    defer { watchdog.cancel() }

                    process.waitUntilExit()

                    guard process.terminationStatus == 0 else {
                        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        let err = String(data: errData, encoding: .utf8) ?? ""
                        continuation.resume(throwing: ADBError.commandFailed(
                            exitCode: process.terminationStatus, stderr: err))
                        return
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 搜索手机文件（从指定路径向下递归，文件和文件夹都搜）
    /// 返回格式：每行 "d|path" 或 "f|path"，前缀标记文件类型
    func searchFiles(device: String, query: String, from path: String) throws -> String {
        // 输入校验：path 只允许安全字符 (字母数字、/、.、-、_)
        let pathSafeChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-")
        guard path.rangeOfCharacter(from: pathSafeChars.inverted) == nil else {
            throw ADBError.invalidSearchInput("path contains unsafe characters")
        }
        // 输入校验：query 只允许安全字符 (字母数字、空格、.、-、_、中文字符)
        var querySafeChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._-")
        querySafeChars.insert(charactersIn: UnicodeScalar(0x4E00)!...UnicodeScalar(0x9FFF)!)  // CJK Unified Ideographs
        querySafeChars.insert(charactersIn: UnicodeScalar(0x3400)!...UnicodeScalar(0x4DBF)!)  // CJK Extension A
        guard query.rangeOfCharacter(from: querySafeChars.inverted) == nil else {
            throw ADBError.invalidSearchInput("query contains unsafe characters")
        }
        let escPath = shellEscape(path)
        // 查询词在单引号内，只需转义单引号本身（shellQuote 逻辑）
        let safeQuery = query.replacingOccurrences(of: "'", with: "'\\''")
        let cmd = """
            find "\(escPath)" -iname '*\(safeQuery)*' 2>/dev/null | head -100 | while read p; do \
            if [ -d "$p" ]; then echo "d|$p|0"; else echo "f|$p|$(stat -c%s "$p" 2>/dev/null || echo 0)"; fi; \
            done
            """
        androidFMLog("searchFiles: query=\(query) path=\(path)")
        let output = try shell(device: device, command: cmd, retryOnTimeout: true)
        androidFMLog("searchFiles output lines: \(output.components(separatedBy: "\n").count)")
        return output
    }
    
    func heartbeat() -> Bool {
        do {
            let output = try run(["devices"], timeout: C.adbHeartbeat)
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }

    /// 清理上次崩溃/强制退出残留的临时文件
    static func cleanupStaleTempFiles() {
        let prefixes = [C.tmpThumbPrefix, C.tmpPreviewPrefix, C.tmpApkPrefix]
        let fm = FileManager.default
        for prefix in prefixes {
            let dir = (prefix as NSString).deletingLastPathComponent
            guard fm.fileExists(atPath: dir) else { continue }
            guard let base = prefix.components(separatedBy: "/").last, !base.isEmpty else { continue }
            let files = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
            for f in files where f.hasPrefix(base) {
                let full = "\(dir)/\(f)"
                try? fm.removeItem(atPath: full)
            }
        }
    }

    // MARK: - 屏幕镜像

    func launchScrcpy(deviceId: String) {
        guard let scrcpyPath = Bundle.main.path(forResource: "scrcpy", ofType: nil),
              let serverPath = Bundle.main.path(forResource: "scrcpy-server", ofType: nil) else {
            androidFMLog("[ADBService] scrcpy: missing embedded binaries")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: scrcpyPath)
        process.arguments = ["-s", deviceId, "--window-title", "屏幕镜像"]
        process.environment = [
            "ADB": adbPath,
            "SC_SERVER_PATH": serverPath
        ]
        do {
            try process.run()
            androidFMLog("[ADBService] scrcpy launched for device \(deviceId)")
        } catch {
            androidFMLog("[ADBService] scrcpy launch failed: \(error)")
        }
    }
}

/// 获取本机当前 WiFi IP 地址
// MARK: - ADB 错误类型

public enum ADBError: LocalizedError {
    case commandFailed(exitCode: Int32, stderr: String)
    case deviceNotFound(String)
    case parseError(String)
    case adbNotInstalled(String)
    case invalidSearchInput(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let code, let stderr):
            let truncated = stderr.count > 200 ? String(stderr.prefix(200)) + "…" : stderr
            return "ADB \(code): \(truncated)"
        case .deviceNotFound(let id):
            return "Device \(id) not found"
        case .parseError(let msg):
            return "Parse error: \(msg)"
        case .adbNotInstalled(let msg):
            return msg
        case .invalidSearchInput(let msg):
            return "Invalid search input: \(msg)"
        }
    }
}

// MARK: - ExitCodeBox（用于 terminationHandler 闭包中安全传值）

final class ExitCodeBox: @unchecked Sendable {
    var value: Int32 = 0
}