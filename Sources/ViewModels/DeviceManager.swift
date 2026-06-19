import Observation
import Network

@MainActor
@Observable
final class DeviceManager {
    private let adb = ADBService.shared
    private var pollingTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var networkMonitor: NWPathMonitor?

    var devices: [Device] = []
    var selectedDevice: Device?
    var errorMessage: String?
    var onDisconnect: (() -> Void)?
    private var consecutiveFailures = 0
    private var isEnablingWireless = false
    
    // 无线设备自动重连：记录上次 WiFi IP
    private var lastWiFiIP: String = ""

    func startPolling() {
        androidFMLog("DeviceManager.startPolling()")
        pollingTask?.cancel()
        heartbeatTask?.cancel()
        pollingTask = Task {
            // 启动时不清已有无线连接
            androidFMLog("Polling loop started")
            var tickCount = 0
            while !Task.isCancelled {
                await refreshDevices()
                tickCount += 1
                // 每 heartbeatIntervalTicks 做一次心跳
                if tickCount % C.heartbeatIntervalTicks == 0 { await checkHeartbeat() }
                // 每 networkCheckIntervalTicks 检查网络是否变了
                if tickCount % C.networkCheckIntervalTicks == 0 { await checkNetworkChange() }
                try? await Task.sleep(for: .seconds(C.pollingIntervalSec))
            }
        }
        startNetworkMonitor()
    }

    func stopPolling() {
        androidFMLog("DeviceManager.stopPolling()")
        pollingTask?.cancel()
        heartbeatTask?.cancel()
        networkMonitor?.cancel()
    }

    func refreshDevices() async {
        do {
            let newDevices = try await Task {
                try ADBService.shared.listDevices()
            }.value
            androidFMLog("refreshDevices: got \(newDevices.count) devices, selectedDevice=\(selectedDevice?.id ?? "nil")")
            // 保留已有的 displayName，避免 getDeviceInfo 偶发超时冲掉正确名字
            var mergedDevices = newDevices
            for i in mergedDevices.indices {
                if mergedDevices[i].displayName.isEmpty,
                   let old = devices.first(where: { $0.id == mergedDevices[i].id }),
                   !old.displayName.isEmpty {
                    mergedDevices[i].displayName = old.displayName
                }
            }
            devices = mergedDevices
            errorMessage = nil
            consecutiveFailures = 0
            if let selected = selectedDevice, !devices.contains(where: { $0.id == selected.id }) {
                selectedDevice = nil
                // 通知 FileBrowser 清理残留状态（搜索、选择等）
                onDisconnect?()
            }
        } catch {
            consecutiveFailures += 1
            androidFMLog("refreshDevices ERROR (#\(consecutiveFailures)): \(error)")
            if consecutiveFailures >= 10 {
                errorMessage = "设备连接异常 (连续 \(consecutiveFailures) 次)"
            }
        }
    }

    func connectWireless(ip: String, port: Int = C.adbPort) async {
        do {
            _ = try await Task {
                try ADBService.shared.connectWireless(ip: ip, port: port)
            }.value
            await refreshDevices()
        } catch {
            errorMessage = "连接失败: \(error.localizedDescription)"
        }
    }

    /// USB 设备：一键切 TCP 模式 + 获取 IP + 自动无线连
    /// 策略 A: tcpip → 检测 wifi_enabled=1 → 直连 WiFi IP
    /// 策略 B: USB 端口转发隧道 (adb forward → localhost) 绕过网络问题
    /// 策略 C: 全失败 → 给出 IP 让用户手动操作
    func enableWireless(for device: Device) async {
        guard device.state == .online else {
            errorMessage = "设备不在线"
            return
        }
        guard !isEnablingWireless else {
            androidFMLog("enableWireless: already in progress, skip")
            return
        }
        isEnablingWireless = true
        defer { isEnablingWireless = false }

        let serial = device.id
        androidFMLog("enableWireless: start for \(serial)")

        // Step 1: tcpip
        do {
            _ = try await Task {
                try ADBService.shared.enableTCP(device: serial)
            }.value
            androidFMLog("enableWireless: tcpip 5555 done")
        } catch {
            errorMessage = "切换 TCP 模式失败: \(error.localizedDescription)"
            return
        }

        // Step 2: 等 adbd 重启
        try? await Task.sleep(for: .seconds(3))
        await refreshDevices()

        // Step 3: 获取 IP
        var ip = ""
        for attempt in 1...3 {
            do {
                ip = try await Task {
                    try ADBService.shared.getDeviceIP(device: serial)
                }.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !ip.isEmpty { break }
                androidFMLog("getDeviceIP attempt \(attempt): got empty string")
            } catch {
                androidFMLog("getDeviceIP attempt \(attempt) failed: \(error)")
                if attempt < 3 { try? await Task.sleep(for: .seconds(1)) }
            }
        }
        guard !ip.isEmpty else {
            errorMessage = "无法获取手机 IP，请检查 WiFi 连接"
            return
        }
        androidFMLog("enableWireless: got IP=\(ip)")

        // Step 4: 检测无线调试开关
        let wifiEnabled: String
        do {
            wifiEnabled = try await Task {
                try ADBService.shared.run(
                    ["-s", serial, "shell", "settings get global adb_wifi_enabled"],
                    timeout: 3
                )
            }.value.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            wifiEnabled = ""
        }
        androidFMLog("enableWireless: adb_wifi_enabled=\(wifiEnabled)")

        // Step 5a: 直连 WiFi IP（失败时自动重启 adb server 重试一次）
        do {
            let result = try await Task {
                try ADBService.shared.connectWireless(ip: ip)
            }.value
            androidFMLog("enableWireless: direct connect OK: \(result)")
            await refreshDevices()
            return
        } catch {
            androidFMLog("enableWireless: direct connect failed: \(error), restarting adb server")
            // adb server 状态可能卡死，杀 server 重试
            _ = try? await Task {
                try ADBService.shared.run(["kill-server"], timeout: 3)
            }.value
            try? await Task.sleep(for: .seconds(1))
            _ = try? await Task {
                try ADBService.shared.run(["start-server"], timeout: 5)
            }.value
            try? await Task.sleep(for: .seconds(1))
            do {
                let result = try await Task {
                    try ADBService.shared.connectWireless(ip: ip)
                }.value
                androidFMLog("enableWireless: retry connect OK: \(result)")
                await refreshDevices()
                return
            } catch {
                androidFMLog("enableWireless: retry connect also failed: \(error)")
            }
        }

        // Step 5b: USB 端口转发隧道（只清理当前设备转发）
        do {
            _ = try? await Task {
                try ADBService.shared.run(["-s", serial, "forward", "--remove", "tcp:5555"], timeout: 2)
            }.value
            _ = try await Task {
                try ADBService.shared.run(["-s", serial, "forward", "tcp:5555", "tcp:5555"], timeout: 3)
            }.value
            androidFMLog("enableWireless: forward set up, trying localhost")
            let result = try await Task {
                try ADBService.shared.connectWireless(ip: "localhost")
            }.value
            androidFMLog("enableWireless: localhost connect OK: \(result)")
            await refreshDevices()
            // 检查是否真的 online（不是 offline）
            if devices.contains(where: { $0.id.contains("localhost") && $0.state == .online }) {
                androidFMLog("enableWireless: localhost device online!")
                return
            }
            androidFMLog("enableWireless: localhost device offline — adbd not in TCP mode")
        } catch {
            androidFMLog("enableWireless: localhost connect failed: \(error)")
        }

        // Step 5c: 全失败 → 给精确指导
        if wifiEnabled != "1" {
            errorMessage = """
            自动无线连接失败

            此手机 (Android 11+) 需手动开启无线调试：
            1. 设置 → 开发者选项 → 无线调试 → 打开
            2. 在侧边栏「无线连接」输入：\(ip):5555
            """
        } else {
            errorMessage = "无法连接到 \(ip):5555，请检查 Mac 和手机是否在同一 WiFi 网络"
        }
    }

    func disconnect(device: Device) async {
        guard device.connectionType == .wireless else { return }
        do {
            _ = try await Task {
                try ADBService.shared.disconnectWireless(serial: device.id)
            }.value
            await refreshDevices()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - 心跳 & 网络监控
    
    private func checkHeartbeat() async {
        let alive = await Task { ADBService.shared.heartbeat() }.value
        if !alive {
            androidFMLog("ADB server 无响应")
        }
    }
    
    private func checkNetworkChange() async {
        // 获取当前 WiFi IP
        let currentIP = await Task { ADBService.shared.getCurrentWiFiIP() }.value
        guard !currentIP.isEmpty else { return }
        
        if lastWiFiIP != currentIP {
            androidFMLog("网络变更: \(lastWiFiIP) → \(currentIP)")
            lastWiFiIP = currentIP
            // 重连所有无线设备
            for device in devices where device.connectionType == .wireless {
                androidFMLog("尝试重连无线设备: \(device.id)")
                _ = try? await Task {
                    _ = try ADBService.shared.run(["connect", device.id], timeout: 10)
                }.value
            }
        }
    }
    
    private func startNetworkMonitor() {
        networkMonitor?.cancel()
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                self?.lastWiFiIP = ""
                await self?.checkNetworkChange()
            }
        }
        networkMonitor?.start(queue: .global())
    }
}
