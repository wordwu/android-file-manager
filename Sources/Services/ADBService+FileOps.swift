import Foundation

extension ADBService {
    // MARK: - 文件浏览 + 操作 + 传输
    // MARK: - 文件浏览

    func listFiles(device: String, path: String) throws -> [FileItem] {
        let dirPath = path.hasSuffix("/") ? path : "\(path)/"
        var items: [FileItem] = []

        // 方案 1: ls -la（一次调用拿全部信息，性能最优）
        let escPath1 = shellEscape(dirPath)
        do {
            let lsOutput = try run(["-s", device, "shell", "ls -la \"\(escPath1)\""], retryOnTimeout: true)
            if !lsOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items = parseLsLaOutput(lsOutput, dirPath: path)
                if items.isEmpty {
                    androidFMLog("listFiles: ls -la 解析出 0 条, output=\(lsOutput.prefix(200))")
                }
            }
        } catch {
            androidFMLog("listFiles: ls -la 失败: \(error)")
        }

        // 方案 2: find + stat 回退（兼容老设备的 toybox/busybox）
        if items.isEmpty {
            androidFMLog("listFiles: ls -la 未返回数据，回退 find + stat, path=\(dirPath)")
            let escapedDir = shellEscape(dirPath)
            let cmd = "find \"\(escapedDir)\" -maxdepth 1 -mindepth 1 2>/dev/null | while read f; do s=$(stat -c \"%s|%Y\" \"$f\" 2>/dev/null || echo \"0|0\"); [ -d \"$f\" ] && echo \"d|$s|$f\" || echo \"f|$s|$f\"; done"
            do {
                let output = try run(["-s", device, "shell", cmd], timeout: 5, retryOnTimeout: true)
                if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    items = parseFindStatOutput(output)
                    androidFMLog("listFiles: find+stat → \(items.count) items")
                }
            } catch {
                androidFMLog("listFiles: find+stat 失败: \(error)")
            }
        }

        // 方案 3: ls -1a 最后兜底
        if items.isEmpty {
            androidFMLog("listFiles: no items, trying ls -1aF fallback")
            // 先试 -F（文件名后缀 / 标记目录），失败回退 -1a
            let escPath3 = shellEscape(dirPath)
            let simpleOut: String
            if let fOut = try? run(["-s", device, "shell", "ls -1aF \"\(escPath3)\""], retryOnTimeout: true),
               !fOut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                simpleOut = fOut
            } else {
                androidFMLog("listFiles: ls -1aF failed, trying ls -1ap")
                simpleOut = (try? run(["-s", device, "shell", "ls -1ap \"\(escPath3)\""], retryOnTimeout: true)) ?? ""
            }
            items = parseLs1aOutput(simpleOut, dirPath: path, usesF: true)
        }

        // 方案 4: ls -1a + test -d（最后兜底，逐文件判类型）
        if items.isEmpty {
            androidFMLog("listFiles: ls -1ap failed, trying ls -1a + test -d")
            let escDir = shellEscape(dirPath)
            let cmd = "cd -P \"\(escDir)\" 2>/dev/null && ls -1a | while read f; do [ \"$f\" = \".\" ] && continue; [ \"$f\" = \"..\" ] && continue; if [ -d \"$f\" ]; then echo \"d|$f\"; else echo \"f|$f\"; fi; done"
            if let output = try? run(["-s", device, "shell", cmd], retryOnTimeout: true),
               !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items = parseTestDOutput(output, dirPath: path)
            }
        }

        androidFMLog("listFiles: \(items.count) items from \(path)")
        return items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    
    // MARK: - 文件操作

    func deleteItem(device: String, path: String) throws {
        _ = try run(["-s", device, "shell", "rm -rf \"\(shellEscape(path))\""])
    }

    func createDirectory(device: String, path: String) throws {
        _ = try run(["-s", device, "shell", "mkdir -p \"\(shellEscape(path))\""])
    }

    func renameItem(device: String, from oldPath: String, to newPath: String) throws {
        let cmd = "mv \"\(shellEscape(oldPath))\" \"\(shellEscape(newPath))\""
        androidFMLog("renameItem: adb -s \(device) shell \(cmd)")
        _ = try run(["-s", device, "shell", cmd], retryOnTimeout: true)
    }

    /// 执行通用 shell 命令，返回 stdout
    func shell(device: String, command: String, retryOnTimeout: Bool = false) throws -> String {
        return try run(["-s", device, "shell", command], retryOnTimeout: retryOnTimeout)
    }

    // MARK: - 文件传输（异步 + 进度）

    func pushFile(device: String, localPath: String, remotePath: String,
                  progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        let fileSize: Int64
        if let attrs = try? fileManager.attributesOfItem(atPath: localPath),
           let size = attrs[.size] as? Int64 {
            fileSize = size
        } else {
            androidFMLog("[ADBService] pushFile: failed to get file size for \(localPath)")
            fileSize = 0
        }
        try await runWithProgress(["-s", device, "push", localPath, remotePath],
                                   totalBytes: fileSize, progress: progress)
    }

    func pullFile(device: String, remotePath: String, localPath: String,
                  progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        try await runWithProgress(["-s", device, "pull", remotePath, localPath],
                                   totalBytes: 0, progress: progress)
    }

    // MARK: - aapt 路径
    
    /// 查找本地 aapt / aapt2 工具路径
    /// 扫描顺序：App 内嵌 → Android SDK build-tools（按版本降序）→ 系统 PATH
    var aaptPath: String? {
        // 1. App 内嵌 aapt / aapt2
        if let bundledAapt = Bundle.main.path(forResource: "aapt", ofType: nil),
           fileManager.isExecutableFile(atPath: bundledAapt) {
            return bundledAapt
        }
        if let bundledAapt2 = Bundle.main.path(forResource: "aapt2", ofType: nil),
           fileManager.isExecutableFile(atPath: bundledAapt2) {
            return bundledAapt2
        }

        // 2. 扫描 Android SDK build-tools（按版本降序，取最新）
        let androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"]
            ?? "\(NSHomeDirectory())/android-sdk"
        let buildToolsDir = "\(androidHome)/build-tools"
        if let versions = try? fileManager.contentsOfDirectory(atPath: buildToolsDir) {
            let sorted = versions.sorted(by: >)
            for v in sorted {
                let aapt = "\(buildToolsDir)/\(v)/aapt"
                if fileManager.isExecutableFile(atPath: aapt) { return aapt }
                let aapt2 = "\(buildToolsDir)/\(v)/aapt2"
                if fileManager.isExecutableFile(atPath: aapt2) { return aapt2 }
            }
        }

        // 3. 系统 PATH 中的 aapt
        let whichAapt = Process()
        whichAapt.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichAapt.arguments = ["aapt"]
        let pa = Pipe()
        whichAapt.standardOutput = pa
        try? whichAapt.run()
        whichAapt.waitUntilExit()
        if whichAapt.terminationStatus == 0 {
            let da = pa.fileHandleForReading.readDataToEndOfFile()
            let sysAapt = String(data: da, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !sysAapt.isEmpty && fileManager.isExecutableFile(atPath: sysAapt) { return sysAapt }
        }

        // 4. 系统 PATH 中的 aapt2
        let whichAapt2 = Process()
        whichAapt2.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichAapt2.arguments = ["aapt2"]
        let p2 = Pipe()
        whichAapt2.standardOutput = p2
        try? whichAapt2.run()
        whichAapt2.waitUntilExit()
        if whichAapt2.terminationStatus == 0 {
            let d2 = p2.fileHandleForReading.readDataToEndOfFile()
            let sysAapt2 = String(data: d2, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !sysAapt2.isEmpty && fileManager.isExecutableFile(atPath: sysAapt2) { return sysAapt2 }
        }

        return nil
    }

    // MARK: - 图标缓存目录
    
    /// 图标缓存路径：~/Library/Caches/com.altairzheng.androidfm/Icons
    var iconCacheDir: String {
        let dir = "\(NSHomeDirectory())/Library/Caches/com.altairzheng.androidfm/Icons"
        try? fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }
    
    // MARK: - APK 信息
    
    /// 解析 APK 的应用名、包名、版本、权限、SDK 信息
    /// 先从手机拉取到本地临时文件，再用本地 aapt 解析（手机上没有 aapt）
    func getAPKInfo(device: String, remotePath: String) async throws -> APKInfo {
        let esc = shellEscape(remotePath)

        // 获取文件大小
        let sizeOutput = try run(["-s", device, "shell", "stat -c %s \"\(esc)\" 2>/dev/null || wc -c < \"\(esc)\""], timeout: 8)
        let fileSize = Int64(sizeOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        // 拉取 APK 到本地临时目录
        let tmpPath = "\(C.tmpApkPrefix)\(UUID().uuidString).apk"
        defer { try? fileManager.removeItem(atPath: tmpPath) }

        try await pullFile(device: device, remotePath: remotePath, localPath: tmpPath) { _, _ in }

        // 优先用本地 aapt 解析
        if let aapt = aaptPath {
            let badging = try runLocal(aapt, arguments: ["dump", "badging", tmpPath], timeout: 15)
            return APKInfo(fromBadging: badging, fileSize: fileSize)
        }

        // 回退：尝试设备上的 aapt（部分 ROM 自带）
        let fallbackBadging = (try? run(["-s", device, "shell", "aapt dump badging \"\(esc)\" 2>/dev/null"], timeout: 15)) ?? ""
        if !fallbackBadging.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return APKInfo(fromBadging: fallbackBadging, fileSize: fileSize)
        }

        // 最终兜底：只用文件大小
        return APKInfo(fromBadging: "", fileSize: fileSize)
    }
}

// MARK: - ls 输出解析函数（顶层，供测试和 listFiles 使用）

/// 解析 ls -la 输出
/// ls -la 固定结构：权限 硬链接 owner group 大小 月 日 时间/年份 文件名...
/// 文件名可能含空格，从第 9 列(token[8])开始全部拼接

func parseLsDate(_ dateStr: String) -> Date? {
    // 尝试标准英文格式
    let enFormats = [
        "MMM d HH:mm",     // Jun 10 14:30
        "MMM d  yyyy",     // Jan 10  2025 (双空格)
        "MMM d yyyy",      // Jan 10 2025
        "yyyy-MM-dd HH:mm",
    ]

    let enLocale = Locale(identifier: "en_US_POSIX")
    for fmt in enFormats {
        let df = DateFormatter()
        df.locale = enLocale
        df.dateFormat = fmt
        if let date = df.date(from: dateStr) {
            return date
        }
    }

    // 中文 locale 日期格式（如 "6月 10日 14:30" 或 "1月 10 2025"）
    let zhFormats = [
        "M月 d日 HH:mm",
        "M月 d HH:mm",
        "M月 d日 yyyy",
        "M月 d yyyy",
        "yyyy年M月d日 HH:mm",
        "yyyy年M月d日",
    ]

    let zhLocale = Locale(identifier: "zh_CN")
    for fmt in zhFormats {
        let df = DateFormatter()
        df.locale = zhLocale
        df.dateFormat = fmt
        if let date = df.date(from: dateStr) {
            return date
        }
    }

    // ISO 8601 兜底
    if let date = ISO8601DateFormatter().date(from: dateStr) {
        return date
    }

    return nil
}

/// 解析 ls -la 输出 → [FileItem]
/// 自动检测日期格式：
/// - US: "Mon DD HH:MM" 或 "Mon DD YYYY" （parts[5..7] 为日期 3 列，name 从 parts[8] 开始，最少 9 列）
/// - ISO: "YYYY-MM-DD HH:MM" （parts[5..6] 为日期 2 列，name 从 parts[7] 开始，最少 8 列）
func parseLsLaOutput(_ output: String, dirPath: String) -> [FileItem] {
    var items: [FileItem] = []
    let lines = output.components(separatedBy: "\n")
    let isoDatePattern = try? NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}$")
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.first != "t" else { continue }
        let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let perms: String
        let size: Int64
        let dateStr: String
        let name: String

        // 自动识别日期格式：parts[5] 是否为 YYYY-MM-DD
        if parts.count >= 8,
           let isoPat = isoDatePattern,
           isoPat.firstMatch(in: parts[5], range: NSRange(0..<parts[5].utf16.count)) != nil {
            // ISO 日期：parts[5]=YYYY-MM-DD, parts[6]=HH:MM
            perms = parts[0]
            size = Int64(parts[4]) ?? 0
            dateStr = "\(parts[5]) \(parts[6])"
            name = parts[7...].joined(separator: " ")
        } else if parts.count >= 9 {
            // US 日期：parts[5]=Mon, parts[6]=DD, parts[7]=HH:MM/YYYY
            perms = parts[0]
            size = Int64(parts[4]) ?? 0
            dateStr = parts[5..<8].joined(separator: " ")
            name = parts[8...].joined(separator: " ")
        } else {
            continue
        }

        let isDir = perms.hasPrefix("d")
        let path = dirPath.hasSuffix("/") ? dirPath + name : "\(dirPath)/\(name)"
        let modDate = parseLsDate(dateStr)
        items.append(FileItem(name: name, path: path, isDirectory: isDir, size: size, permissions: perms, modifiedDate: modDate))
    }
    return items
}

/// 解析 find + stat 管道输出 → [FileItem]
/// 输入格式: d|size|timestamp|/path/to/file (每行一条，文件夹前缀 d，文件前缀 f)
func parseFindStatOutput(_ output: String) -> [FileItem] {
    var items: [FileItem] = []
    for line in output.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count >= 3 else { continue }
        let isDir = trimmed.hasPrefix("d|")
        guard isDir || trimmed.hasPrefix("f|") else { continue }
        let parts = (trimmed as NSString).substring(from: 2).components(separatedBy: "|")
        guard parts.count >= 3, let size = Int64(parts[0]) else { continue }
        let path = parts.dropFirst(2).joined(separator: "|")  // 路径可能含 |
        guard !path.isEmpty else { continue }
        let name = (path as NSString).lastPathComponent
        let timestamp = Double(parts[1]).map { Date(timeIntervalSince1970: $0) }
        items.append(FileItem(name: name, path: path, isDirectory: isDir, size: size, permissions: "", modifiedDate: timestamp))
    }
    return items
}

/// 解析 ls -1aF 或 ls -1ap 输出 → [FileItem]
func parseLs1aOutput(_ output: String, dirPath: String, usesF: Bool) -> [FileItem] {
    var items: [FileItem] = []
    for line in output.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        let isDir: Bool
        let name: String
        // ls -1aF 会给文件加后缀：/ 目录 * 可执行 @ 符号链接 | FIFO
        // 需要去除这些标记
        let trailing = trimmed.last
        let stripped: String
        if let t = trailing, t == "/" || t == "*" || t == "@" || t == "|" {
            isDir = t == "/"
            stripped = String(trimmed.dropLast())
        } else {
            isDir = false
            stripped = trimmed
        }
        name = stripped
        let path = dirPath.hasSuffix("/") ? dirPath + name : "\(dirPath)/\(name)"
        items.append(FileItem(name: name, path: path, isDirectory: isDir, size: 0, permissions: "", modifiedDate: nil))
    }
    return items
}

/// 解析 test -d 回退输出 → [FileItem]
/// 输入格式: d|filename (目录) / f|filename (文件)，每行一条
func parseTestDOutput(_ output: String, dirPath: String) -> [FileItem] {
    var items: [FileItem] = []
    for line in output.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { continue }
        let isDir = trimmed.hasPrefix("d|")
        guard isDir || trimmed.hasPrefix("f|") else { continue }
        let name = String(trimmed.dropFirst(2))
        guard !name.isEmpty, name != ".", name != ".." else { continue }
        let path = dirPath.hasSuffix("/") ? dirPath + name : "\(dirPath)/\(name)"
        items.append(FileItem(name: name, path: path, isDirectory: isDir, size: 0, permissions: "", modifiedDate: nil))
    }
    return items
}
