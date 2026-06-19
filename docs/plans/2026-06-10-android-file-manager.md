# Android 文件管理器 — macOS 原生实现计划

> 使用 subagent-driven-development 逐任务执行。每个任务完成后提交。

**目标：** 用 SwiftUI 构建 macOS 原生安卓文件管理器，底层通过 ADB 与手机通信。

**架构：** SwiftUI 三栏布局 + ADB Service 层 + 串行命令队列。SPM 管理依赖，零第三方库。

**技术栈：** Swift 6.3 + SwiftUI (macOS 15+) + ADB 1.0.41 + SPM

**ADB 路径：** `~/android-sdk/platform-tools/adb`（运行时动态检测）

---

## 项目结构总览

```
AndroidFileManager/
├── Package.swift
├── Sources/
│   ├── App/
│   │   └── AndroidFileManagerApp.swift
│   ├── Models/
│   │   ├── Device.swift
│   │   ├── FileItem.swift
│   │   └── TransferTask.swift
│   ├── Services/
│   │   └── ADBService.swift
│   ├── ViewModels/
│   │   ├── DeviceManager.swift
│   │   ├── FileBrowser.swift
│   │   └── TransferManager.swift
│   └── Views/
│       ├── ContentView.swift
│       ├── Sidebar/DeviceListView.swift
│       ├── Browser/
│       │   ├── FileListView.swift
│       │   ├── FileRowView.swift
│       │   └── PathBarView.swift
│       ├── Preview/FilePreviewView.swift
│       └── Transfer/TransferPanelView.swift
```

---

## Phase 0：项目脚手架（5 个任务）

### Task 0.1: 创建 SPM 项目骨架

**文件：**
- 创建：`Package.swift`
- 创建：`Sources/App/AndroidFileManagerApp.swift`

`Package.swift`：

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AndroidFileManager",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "AndroidFileManager",
            path: "Sources"
        )
    ]
)
```

`AndroidFileManagerApp.swift`：

```swift
import SwiftUI

@main
struct AndroidFileManagerApp: App {
    @State private var deviceManager = DeviceManager()
    @State private var fileBrowser = FileBrowser()
    @State private var transferManager = TransferManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(deviceManager)
                .environment(fileBrowser)
                .environment(transferManager)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
```

**验证：**
```bash
cd ~/Desktop/AndroidFileManager && swift build
```
预期：编译成功，无报错。

### Task 0.2: 创建三个 Model 文件

**文件：**
- 创建：`Sources/Models/Device.swift`
- 创建：`Sources/Models/FileItem.swift`
- 创建：`Sources/Models/TransferTask.swift`

`Device.swift`：

```swift
import Foundation

struct Device: Identifiable, Hashable {
    let id: String          // serial number
    let model: String       // e.g. "Pixel_8"
    let state: DeviceState
    let connectionType: ConnectionType

    enum DeviceState: String {
        case online
        case offline
        case unauthorized
    }

    enum ConnectionType: String {
        case usb
        case wireless
    }
}
```

`FileItem.swift`：

```swift
import Foundation

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String         // 全路径，如 /sdcard/DCIM/Camera
    let isDirectory: Bool
    let size: Int64          // bytes, directory 时为 0
    let permissions: String  // e.g. "drwxrwx---"
    let modifiedDate: Date?

    var sizeFormatted: String {
        // ByteCountFormatter
        guard !isDirectory else { return "--" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var iconName: String {
        if isDirectory { return "folder" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo"
        case "mp4", "mkv", "avi", "mov": return "film"
        case "mp3", "wav", "flac", "aac": return "music.note"
        case "apk": return "shippingbox"
        case "pdf": return "doc.richtext"
        case "zip", "rar", "7z": return "doc.zipper"
        default: return "doc"
        }
    }
}
```

`TransferTask.swift`：

```swift
import Foundation

struct TransferTask: Identifiable {
    let id = UUID()
    let deviceId: String
    let direction: Direction
    let localPath: String
    let remotePath: String
    let fileName: String
    let totalBytes: Int64
    var transferredBytes: Int64 = 0
    var progress: Double {
        totalBytes > 0 ? Double(transferredBytes) / Double(totalBytes) : 0
    }
    var speed: Double = 0   // bytes/sec
    var status: Status = .queued

    enum Direction { case push, pull }
    enum Status: String {
        case queued = "排队中"
        case transferring = "传输中"
        case completed = "已完成"
        case failed = "失败"
    }
}
```

**验证：**
```bash
cd ~/Desktop/AndroidFileManager && swift build
```
预期：编译成功。

### Task 0.3: 创建 ContentView 骨架（三栏布局）

**文件：**
- 创建：`Sources/Views/ContentView.swift`

```swift
import SwiftUI

struct ContentView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(FileBrowser.self) private var fileBrowser
    @Environment(TransferManager.self) private var transferManager

    var body: some View {
        NavigationSplitView {
            DeviceListView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } content: {
            VStack(spacing: 0) {
                PathBarView()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                Divider()
                FileListView()
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: 550)
        } detail: {
            FilePreviewView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 350)
        }
    }
}
```

**验证：** `swift build` 会报缺少 View 文件，但先不管——下一个 Phase 补齐。

---

## Phase 1：ADB Service 层（5 个任务）

### Task 1.1: 创建 ADBService 骨架 + adb 路径检测

**文件：**
- 创建：`Sources/Services/ADBService.swift`

```swift
import Foundation

final class ADBService {
    static let shared = ADBService()

    private let adbPath: String
    private let fileManager = FileManager.default

    private init() {
        // 优先 ANDROID_HOME 环境变量，其次 ~/android-sdk
        let androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"]
            ?? "\(NSHomeDirectory())/android-sdk"
        self.adbPath = "\(androidHome)/platform-tools/adb"

        guard fileManager.isExecutableFile(atPath: adbPath) else {
            fatalError("ADB not found at \(adbPath). Install Android SDK platform-tools.")
        }
    }

    /// 执行 adb 命令，返回 stdout + stderr
    func run(_ arguments: [String], timeout: TimeInterval = 30) throws -> String {
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

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: stdoutData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let err = String(data: stderrData, encoding: .utf8) ?? ""
            throw ADBError.commandFailed(exitCode: process.terminationStatus, stderr: err)
        }

        return output
    }
}

enum ADBError: LocalizedError {
    case commandFailed(exitCode: Int32, stderr: String)
    case deviceNotFound(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let code, let stderr): return "ADB exited \(code): \(stderr)"
        case .deviceNotFound(let id): return "Device \(id) not found"
        case .parseError(let msg): return "Parse error: \(msg)"
        }
    }
}
```

**验证：**
```bash
cd ~/Desktop/AndroidFileManager && swift build
```
预期：编译成功。

### Task 1.2: 实现设备列表解析

在 ADBService 追加：

```swift
/// 返回所有已连接设备
func listDevices() throws -> [Device] {
    let output = try run(["devices", "-l"])
    var devices: [Device] = []

    // 跳过第一行 "List of devices attached"
    for line in output.components(separatedBy: "\n").dropFirst() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        // 格式: "emulator-5554   device product:sdk_gphone64_arm64 model:... device:..."
        let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 2 else { continue }

        let serial = parts[0]
        let stateStr = parts[1]
        let state: Device.DeviceState = switch stateStr {
            case "device": .online
            case "offline": .offline
            default: .unauthorized
        }

        // 解析 model 字段
        var model = "Unknown"
        for part in parts.dropFirst(2) {
            if part.hasPrefix("model:") {
                model = String(part.dropFirst(6))
                break
            }
        }

        // 判断连接类型：无线连接通常包含 IP
        let connectionType: Device.ConnectionType = serial.contains(".")
            ? .wireless : .usb

        devices.append(Device(id: serial, model: model, state: state, connectionType: connectionType))
    }

    return devices
}
```

**验证：** 暂时无测试 — Task 2.1 做 DeviceManager 时一起验证。

### Task 1.3: 实现文件列表解析

在 ADBService 追加：

```swift
/// 列出设备上指定路径的文件
func listFiles(device: String, path: String) throws -> [FileItem] {
    let output = try run(["-s", device, "shell", "ls", "-la", path])
    var items: [FileItem] = []

    for line in output.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        // 跳过 "total XXX" 行
        guard !trimmed.hasPrefix("total ") else { continue }

        // 正则: 权限(10) 链接数 所有者 组 大小 月 日 时间/年 名称
        let pattern = #"^([-dlrwx]{10})\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2})\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else {
            continue
        }

        let perms = String(trimmed[Range(match.range(at: 1), in: trimmed)!])
        let sizeStr = String(trimmed[Range(match.range(at: 2), in: trimmed)!])
        let dateStr = String(trimmed[Range(match.range(at: 3), in: trimmed)!])
        let name = String(trimmed[Range(match.range(at: 4), in: trimmed)!])

        let isDirectory = perms.hasPrefix("d")
        let size = isDirectory ? 0 : (Int64(sizeStr) ?? 0)

        // 解析日期 (Android ls 可能输出不同格式)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let modifiedDate = dateFormatter.date(from: dateStr)

        let fullPath = path.hasSuffix("/") ? "\(path)\(name)" : "\(path)/\(name)"

        items.append(FileItem(
            name: name,
            path: fullPath,
            isDirectory: isDirectory,
            size: size,
            permissions: perms,
            modifiedDate: modifiedDate
        ))
    }

    // 目录在前，按名称排序
    return items.sorted { a, b in
        if a.isDirectory != b.isDirectory { return a.isDirectory }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}

/// 获取设备磁盘信息
func diskInfo(device: String) throws -> (used: Int64, total: Int64) {
    let output = try run(["-s", device, "shell", "df", "-h", "/sdcard"])
    // 取第二行: Filesystem  Size  Used  Avail  Use%  Mounted on
    let lines = output.components(separatedBy: "\n")
    guard lines.count >= 2 else { return (0, 0) }
    let parts = lines[1].components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    guard parts.count >= 6 else { return (0, 0) }
    // df -h 输出人类可读格式，简单处理
    return (0, 0) // 简化为先用文件数，后续优化
}
```

**坑点标注：** Android 的 `ls` 命令输出格式因 ROM 不同可能变化（特别是日期格式）。如果实际设备上解析失败，需要 `adb shell "ls -la --time-style=long-iso PATH"` 来统一格式。

**验证：** `swift build`

### Task 1.4: 实现文件操作命令

在 ADBService 追加：

```swift
func deleteItem(device: String, path: String) throws {
    _ = try run(["-s", device, "shell", "rm", "-rf", path])
}

func createDirectory(device: String, path: String) throws {
    _ = try run(["-s", device, "shell", "mkdir", "-p", path])
}

func renameItem(device: String, from oldPath: String, to newPath: String) throws {
    _ = try run(["-s", device, "shell", "mv", oldPath, newPath])
}
```

**验证：** `swift build`

### Task 1.5: 实现文件传输命令

在 ADBService 追加：

```swift
/// push: 上传文件到设备
func pushFile(device: String, localPath: String, remotePath: String,
              progress: @escaping (Int64, Int64) -> Void) throws {
    let fileSize = (try? FileManager.default.attributesOfItem(atPath: localPath)[.size] as? Int64) ?? 0
    _ = try runAndTrack(["-s", device, "push", localPath, remotePath],
                         totalBytes: fileSize, progress: progress)
}

/// pull: 从设备下载文件
func pullFile(device: String, remotePath: String, localPath: String,
              progress: @escaping (Int64, Int64) -> Void) throws {
    _ = try runAndTrack(["-s", device, "pull", remotePath, localPath],
                         totalBytes: 0, progress: progress)
}

/// 带进度跟踪的命令执行
private func runAndTrack(_ args: [String], totalBytes: Int64,
                         progress: @escaping (Int64, Int64) -> Void) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: adbPath)
    process.arguments = args

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    var environment = ProcessInfo.processInfo.environment
    environment["LC_ALL"] = "en_US.UTF-8"
    process.environment = environment

    // 异步读取 stdout，解析进度
    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
        // adb push/pull 输出格式: "Transferring: 1425408/8452096 (16%)"
        if let match = line.firstMatch(of: #/Transferring:\s+(\d+)/(\d+)/#) {
            let current = Int64(match.1) ?? 0
            let total = Int64(match.2) ?? totalBytes
            progress(current, total)
        }
    }

    try process.run()
    process.waitUntilExit()

    stdoutPipe.fileHandleForReading.readabilityHandler = nil

    guard process.terminationStatus == 0 else {
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let err = String(data: errData, encoding: .utf8) ?? ""
        throw ADBError.commandFailed(exitCode: process.terminationStatus, stderr: err)
    }

    return ""
}
```

**验证：** `swift build`

---

## Phase 2：ViewModels（3 个任务）

### Task 2.1: DeviceManager — 设备发现与管理

**文件：**
- 创建：`Sources/ViewModels/DeviceManager.swift`

```swift
import SwiftUI
import Observation

@MainActor
@Observable
final class DeviceManager {
    private let adb = ADBService.shared
    private var pollingTask: Task<Void, Never>?

    var devices: [Device] = []
    var selectedDevice: Device?
    var errorMessage: String?

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await refreshDevices()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refreshDevices() async {
        do {
            devices = try await Task.detached {
                try ADBService.shared.listDevices()
            }.value
            errorMessage = nil
            // 如果当前选中设备断开了，取消选中
            if let selected = selectedDevice, !devices.contains(where: { $0.id == selected.id }) {
                selectedDevice = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func connectWireless(ip: String, port: Int = 5555) async {
        do {
            _ = try await Task.detached {
                try ADBService.shared.run(["connect", "\(ip):\(port)"])
            }.value
            await refreshDevices()
        } catch {
            errorMessage = "连接失败: \(error.localizedDescription)"
        }
    }

    func disconnect(device: Device) async {
        guard device.connectionType == .wireless else { return }
        do {
            _ = try await Task.detached {
                try ADBService.shared.run(["disconnect", device.id])
            }.value
            await refreshDevices()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

**验证：** `swift build`

### Task 2.2: FileBrowser — 文件浏览与导航

**文件：**
- 创建：`Sources/ViewModels/FileBrowser.swift`

```swift
import SwiftUI
import Observation

@MainActor
@Observable
final class FileBrowser {
    private let adb = ADBService.shared

    var currentPath = "/sdcard"
    var files: [FileItem] = []
    var pathStack: [String] = []
    var isLoading = false
    var selectedFile: FileItem?
    var errorMessage: String?

    func loadDirectory(device: String, path: String? = nil) async {
        if let path { currentPath = path }
        isLoading = true
        defer { isLoading = false }

        do {
            files = try await Task.detached { [adb, device = device, path = currentPath] in
                try adb.listFiles(device: device, path: path)
            }.value
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            files = []
        }
    }

    func navigateInto(_ item: FileItem) {
        guard item.isDirectory else { return }
        pathStack.append(currentPath)
        currentPath = item.path
        selectedFile = nil
    }

    func navigateBack() {
        guard !pathStack.isEmpty else { return }
        currentPath = pathStack.removeLast()
    }

    func navigateUp() {
        guard currentPath != "/" else { return }
        currentPath = (currentPath as NSString).deletingLastPathComponent
    }

    func navigateTo(path: String) {
        // 跳到指定目录（面包屑点击）
        currentPath = path
        // 清除该目录之后的栈
        if let idx = pathStack.firstIndex(of: path) {
            pathStack.removeSubrange(idx...)
        }
    }

    func refresh(device: String) async {
        await loadDirectory(device: device)
    }
}
```

**验证：** `swift build`

### Task 2.3: TransferManager — 传输队列

**文件：**
- 创建：`Sources/ViewModels/TransferManager.swift`

```swift
import SwiftUI
import Observation

@MainActor
@Observable
final class TransferManager {
    private let adb = ADBService.shared
    var tasks: [TransferTask] = []
    var isTransferring = false

    func enqueue(task: TransferTask) {
        tasks.append(task)
        processNextIfIdle()
    }

    private func processNextIfIdle() {
        guard !isTransferring else { return }
        guard let idx = tasks.firstIndex(where: { $0.status == .queued }) else {
            isTransferring = false
            return
        }
        isTransferring = true
        processTask(at: idx)
    }

    private func processTask(at idx: Int) {
        let task = tasks[idx]
        tasks[idx].status = .transferring

        Task {
            do {
                if task.direction == .push {
                    try await Task.detached { [adb] in
                        try adb.pushFile(device: task.deviceId,
                                         localPath: task.localPath,
                                         remotePath: task.remotePath) { current, total in
                            Task { @MainActor in
                                if let i = self.tasks.firstIndex(where: { $0.id == task.id }) {
                                    self.tasks[i].transferredBytes = current
                                }
                            }
                        }
                    }.value
                } else {
                    try await Task.detached { [adb] in
                        try adb.pullFile(device: task.deviceId,
                                         remotePath: task.remotePath,
                                         localPath: task.localPath) { current, total in
                            Task { @MainActor in
                                if let i = self.tasks.firstIndex(where: { $0.id == task.id }) {
                                    self.tasks[i].transferredBytes = current
                                }
                            }
                        }
                    }.value
                }

                if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[i].status = .completed
                }
            } catch {
                if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[i].status = .failed
                }
            }

            isTransferring = false
            processNextIfIdle()
        }
    }

    func cancel(taskId: UUID) {
        tasks.removeAll { $0.id == taskId }
        if tasks.isEmpty { isTransferring = false }
    }

    func clearCompleted() {
        tasks.removeAll { $0.status == .completed }
    }
}
```

**验证：** `swift build`

---

## Phase 3：UI 视图（7 个任务）

### Task 3.1: DeviceListView — 侧边栏

**文件：**
- 创建：`Sources/Views/Sidebar/DeviceListView.swift`

```swift
import SwiftUI

struct DeviceListView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @State private var ipAddress = ""
    @State private var port = "5555"

    var body: some View {
        List(selection: Bindable(deviceManager).selectedDevice) {
            Section("设备") {
                if deviceManager.devices.isEmpty {
                    Text("未检测到设备")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                ForEach(deviceManager.devices) { device in
                    HStack {
                        Image(systemName: device.connectionType == .usb ? "cable.connector" : "wifi")
                            .foregroundStyle(device.state == .online ? .green : .red)
                        VStack(alignment: .leading) {
                            Text(device.model)
                                .font(.body)
                            Text(device.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if device.connectionType == .wireless {
                            Button {
                                Task { await deviceManager.disconnect(device: device) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("无线连接") {
                HStack {
                    TextField("IP 地址", text: $ipAddress)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    Text(":")
                    TextField("端口", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                }
                Button {
                    Task { await deviceManager.connectWireless(ip: ipAddress, port: Int(port) ?? 5555) }
                } label: {
                    Label("连接", systemImage: "link")
                }
                .disabled(ipAddress.isEmpty)
            }
        }
        .listStyle(.sidebar)
        .onAppear { deviceManager.startPolling() }
        .onDisappear { deviceManager.stopPolling() }
        .alert("错误", isPresented: .constant(deviceManager.errorMessage != nil)) {
            Button("确定") { deviceManager.errorMessage = nil }
        } message: {
            Text(deviceManager.errorMessage ?? "")
        }
    }
}
```

**验证：** `swift build`

### Task 3.2: PathBarView — 面包屑导航

**文件：**
- 创建：`Sources/Views/Browser/PathBarView.swift`

```swift
import SwiftUI

struct PathBarView: View {
    @Environment(FileBrowser.self) private var fileBrowser

    var body: some View {
        HStack(spacing: 0) {
            // 返回按钮
            Button {
                fileBrowser.navigateBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .disabled(fileBrowser.pathStack.isEmpty)

            Button {
                fileBrowser.navigateUp()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(fileBrowser.currentPath == "/")
            .padding(.leading, 8)

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 8)

            // 面包屑
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(pathComponents, id: \.self) { component in
                        if component != pathComponents.first {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Button(component.name) {
                            fileBrowser.navigateTo(path: component.path)
                        }
                        .buttonStyle(.plain)
                        .font(.callout)
                    }
                }
            }
        }
        .frame(height: 32)
    }

    private var pathComponents: [(name: String, path: String)] {
        let parts = fileBrowser.currentPath.components(separatedBy: "/").filter { !$0.isEmpty }
        var result: [(String, String)] = []
        var accumulated = ""
        for part in parts {
            accumulated += "/\(part)"
            result.append((part, accumulated))
        }
        return result
    }
}
```

**验证：** `swift build`

### Task 3.3: FileRowView — 单行文件项

**文件：**
- 创建：`Sources/Views/Browser/FileRowView.swift`

```swift
import SwiftUI

struct FileRowView: View {
    let item: FileItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.iconName)
                .frame(width: 24)
                .foregroundStyle(item.isDirectory ? .blue : .secondary)

            Text(item.name)
                .lineLimit(1)

            Spacer()

            Text(item.sizeFormatted)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)

            Text(item.modifiedDate?.formatted(date: .numeric, time: .shortened) ?? "--")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}
```

**验证：** `swift build`

### Task 3.4: FileListView — 文件列表主视图

**文件：**
- 创建：`Sources/Views/Browser/FileListView.swift`

```swift
import SwiftUI

struct FileListView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(FileBrowser.self) private var fileBrowser
    @Environment(TransferManager.self) private var transferManager

    @State private var sortOrder: [KeyPathComparator<FileItem>] = [
        .init(\.isDirectory, order: .reverse),
        .init(\.name, order: .forward)
    ]

    var body: some View {
        Group {
            if let device = deviceManager.selectedDevice, device.state == .online {
                VStack(spacing: 0) {
                    if fileBrowser.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if fileBrowser.files.isEmpty {
                        ContentUnavailableView("空目录", systemImage: "folder",
                                               description: Text(fileBrowser.currentPath))
                    } else {
                        Table(fileBrowser.files, selection: Bindable(fileBrowser).selectedFile,
                              sortOrder: $sortOrder) {
                            TableColumn("名称", value: \.name) { item in
                                FileRowView(item: item, isSelected: fileBrowser.selectedFile == item)
                            }
                            .width(min: 200)

                            TableColumn("大小", value: \.size) { item in
                                Text(item.sizeFormatted)
                                    .foregroundStyle(.secondary)
                            }
                            .width(80)

                            TableColumn("修改日期", value: \.modifiedDate ?? .distantPast) { item in
                                Text(item.modifiedDate?.formatted(date: .numeric, time: .shortened) ?? "--")
                                    .foregroundStyle(.secondary)
                            }
                            .width(150)
                        }
                        .onChange(of: device.id) { _, _ in
                            Task { await fileBrowser.loadDirectory(device: device.id) }
                        }
                        .onChange(of: fileBrowser.currentPath) { _, _ in
                            Task { await fileBrowser.refresh(device: device.id) }
                        }
                        .onChange(of: fileBrowser.selectedFile) { _, newValue in
                            // 双击进入目录
                            if let item = newValue, item.isDirectory {
                                fileBrowser.navigateInto(item)
                            }
                        }
                        .contextMenu(forSelectionType: FileItem.self) { items in
                            // 右键菜单 — 后续任务补充
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    deviceManager.selectedDevice == nil ? "选择设备" : "设备未连接",
                    systemImage: deviceManager.selectedDevice == nil ? "iphone.gen3" : "iphone.gen3.slash",
                    description: Text(deviceManager.selectedDevice == nil
                        ? "在侧边栏选择一个已连接的安卓设备"
                        : "设备已断开，请重新连接")
                )
            }
        }
    }
}
```

**验证：** `swift build`

### Task 3.5: FilePreviewView — 预览面板

**文件：**
- 创建：`Sources/Views/Preview/FilePreviewView.swift`

```swift
import SwiftUI

struct FilePreviewView: View {
    @Environment(FileBrowser.self) private var fileBrowser
    @Environment(DeviceManager.self) private var deviceManager

    @State private var previewImage: NSImage?
    @State private var isLoadingPreview = false

    var body: some View {
        Group {
            if let file = fileBrowser.selectedFile, !file.isDirectory {
                VStack(spacing: 0) {
                    // 预览区域
                    if isLoadingPreview {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let image = previewImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                    } else {
                        Image(systemName: file.iconName)
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    Divider()

                    // 文件信息
                    VStack(alignment: .leading, spacing: 4) {
                        Text("文件信息")
                            .font(.headline)
                        Group {
                            infoRow("名称", file.name)
                            infoRow("大小", file.sizeFormatted)
                            infoRow("路径", file.path)
                            infoRow("权限", file.permissions)
                            if let date = file.modifiedDate {
                                infoRow("修改", date.formatted())
                            }
                        }
                        .font(.caption)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("选择文件", systemImage: "doc.text.image",
                                       description: Text("点击文件查看预览和信息"))
            }
        }
        .onChange(of: fileBrowser.selectedFile) { _, newFile in
            loadPreview(newFile)
        }
    }

    private func loadPreview(_ file: FileItem?) {
        previewImage = nil
        guard let file, let device = deviceManager.selectedDevice else { return }

        let imageExts = ["jpg", "jpeg", "png", "gif", "heic", "webp", "bmp"]
        let ext = (file.name as NSString).pathExtension.lowercased()
        guard imageExts.contains(ext) else { return }

        isLoadingPreview = true
        let tmpPath = "/tmp/androidfm_preview_\(UUID().uuidString).\(ext)"
        Task {
            defer { isLoadingPreview = false }
            do {
                try await Task.detached {
                    try ADBService.shared.pullFile(device: device.id, remotePath: file.path,
                                                   localPath: tmpPath) { _, _ in }
                }.value
                previewImage = NSImage(contentsOfFile: tmpPath)
            } catch {
                // 静默失败，预览不是关键功能
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            Text(value)
                .lineLimit(3)
        }
    }
}
```

**验证：** `swift build`

### Task 3.6: TransferPanelView — 底部传输栏

**文件：**
- 创建：`Sources/Views/Transfer/TransferPanelView.swift`

```swift
import SwiftUI

struct TransferPanelView: View {
    @Environment(TransferManager.self) private var transferManager

    var body: some View {
        if !transferManager.tasks.isEmpty {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {
                    // 显示活跃任务数
                    let active = transferManager.tasks.filter { $0.status == .transferring }.count
                    let total = transferManager.tasks.count
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundStyle(.blue)
                    Text("\(active)/\(total) 个任务")
                        .font(.callout)

                    Spacer()

                    Button("清除已完成") {
                        transferManager.clearCompleted()
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .background(.regularMaterial)
        }
    }
}
```

**验证：** `swift build`

### Task 3.7: 将 TransferPanelView 加入 ContentView

**文件：** 修改 `Sources/Views/ContentView.swift`

在 body 最外层包裹一个 VStack，底部加 TransferPanelView：

```swift
var body: some View {
    VStack(spacing: 0) {
        NavigationSplitView {
            DeviceListView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } content: {
            VStack(spacing: 0) {
                PathBarView()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                Divider()
                FileListView()
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: 550)
        } detail: {
            FilePreviewView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 350)
        }

        TransferPanelView()
    }
}
```

**验证：** `swift build`

---

## Phase 4：功能完善（4 个任务）

### Task 4.1: 右键菜单 — 删除/重命名/新建文件夹

修改 `FileListView.swift`，补充 contextMenu：

```swift
.contextMenu(forSelectionType: FileItem.self) { items in
    if let item = items.first {
        Button {
            // 下载
            let panel = NSSavePanel()
            panel.nameFieldStringValue = item.name
            if panel.runModal() == .OK, let url = panel.url {
                let task = TransferTask(
                    deviceId: device.id,
                    direction: .pull,
                    localPath: url.path,
                    remotePath: item.path,
                    fileName: item.name,
                    totalBytes: item.size
                )
                transferManager.enqueue(task: task)
            }
        } label: {
            Label("下载到 Mac", systemImage: "arrow.down")
        }

        Divider()

        Button(role: .destructive) {
            Task {
                try? await Task.detached {
                    try ADBService.shared.deleteItem(device: device.id, path: item.path)
                }.value
                await fileBrowser.refresh(device: device.id)
            }
        } label: {
            Label("删除", systemImage: "trash")
        }

        Button {
            // 重命名弹窗
            // 后续任务实现
        } label: {
            Label("重命名", systemImage: "pencil")
        }
    }

    Button {
        // 新建文件夹
        let newPath = "\(fileBrowser.currentPath)/新建文件夹"
        Task {
            try? await Task.detached {
                try ADBService.shared.createDirectory(device: device.id, path: newPath)
            }.value
            await fileBrowser.refresh(device: device.id)
        }
    } label: {
        Label("新建文件夹", systemImage: "folder.badge.plus")
    }
}
```

**验证：** `swift build`

### Task 4.2: 拖拽上传（从 Finder 拖文件到 FileListView）

修改 `FileListView.swift`，添加 drop 支持：

```swift
.onDrop(of: [.fileURL], isTargeted: .none) { providers in
    guard let device = deviceManager.selectedDevice else { return false }
    for provider in providers {
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
            guard let data = data as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            let remotePath = "\(fileBrowser.currentPath)/\(url.lastPathComponent)"
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let task = TransferTask(
                deviceId: device.id,
                direction: .push,
                localPath: url.path,
                remotePath: remotePath,
                fileName: url.lastPathComponent,
                totalBytes: fileSize
            )
            Task { @MainActor in
                transferManager.enqueue(task: task)
            }
        }
    }
    return true
}
```

**验证：** `swift build`

### Task 4.3: 键盘快捷键

在 `AndroidFileManagerApp.swift` 的 `.commands` 中追加：

```swift
CommandGroup(after: .sidebar) {
    Button("刷新") { Task { await fileBrowser.refresh(device: deviceManager.selectedDevice?.id ?? "") } }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(deviceManager.selectedDevice == nil)
}
CommandMenu("文件") {
    Button("新建文件夹") {
        // 触发新建文件夹
    }
    .keyboardShortcut("n", modifiers: [.shift, .command])
    .disabled(deviceManager.selectedDevice == nil)
}
```

**验证：** `swift build`

### Task 4.4: 错误处理 + 用户提示

- 全局错误状态通过 DeviceManager/FileBrowser 的 `errorMessage` 属性传播
- 每个 View 通过 `.alert` 或 toast 展示
- ADB 未安装时：`ContentUnavailableView` 提示安装 Android SDK

---

## Phase 5：收尾打磨（2 个任务）

### Task 5.1: App 图标 + 暗色模式适配

- 创建 1024x1024 图标，放入 `Resources/Assets.xcassets/AppIcon`
- 所有视图用 `.background(.regularMaterial)` 或系统颜色，暗色模式自动适配
- 验证：`Cmd+Shift+A` 切换暗色模式，检查颜色

### Task 5.2: 最终测试流程

```bash
# 1. 构建
cd ~/Desktop/AndroidFileManager && swift build

# 2. 运行
swift run

# 3. 手动测试检查清单
# ☐ USB 连接设备被检测到
# ☐ 文件列表正确显示
# ☐ 目录导航（双击/面包屑）正常
# ☐ 右键删除文件
# ☐ 拖拽文件上传
# ☐ 右键下载到 Mac
# ☐ 图片预览显示
# ☐ 无线 ADB 连接
# ☐ 传输进度栏显示
# ☐ 暗色模式
# ☐ 键盘快捷键 (Cmd+R)
# ☐ 中文文件名不乱码
```

---

## 坑点速查

| 坑 | 位置 | 应对 |
|----|------|------|
| `ls -la` 日期格式因 ROM 不同 | ADBService.listFiles | 加 `--time-style=long-iso` 参数 |
| 中文文件名 stdout 乱码 | ADBService.run | 已设 `LC_ALL=en_US.UTF-8` |
| `adb push/pull` 大文件进度行重复 | TransferManager | 去重或用最后一行 |
| `/sdcard/Android/data` 不可读 | Android 11+ scoped storage | 提示用户，不是 bug |
| USB 权限被其他 app 抢占 | 启动时 | 提示关闭 Android File Transfer |
| Swift Regex 需要 macOS 13+ | ADBService | 已设 deployment target macOS 15 |

---

## 执行策略

共 **19 个任务**，预估 **4 天**（每天 4-5 小时）。

推荐使用 `subagent-driven-development` 逐任务执行：
1. 每个 Task 一个 subagent，给完整上下文（文件路径 + 代码）
2. 编译验证为硬门槛——`swift build` 不过不算完成
3. Phase 4/5 需要真机测试，给我截图反馈

---

**Plan complete. Ready to execute.**
