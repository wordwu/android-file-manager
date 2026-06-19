import Foundation

extension ADBService {
    // MARK: - 设备管理 + 网络
    // MARK: - 设备管理

    func listDevices() throws -> [Device] {
        let output = try run(["devices", "-l"], timeout: 8)
        var devices: [Device] = []

        for line in output.components(separatedBy: "\n").dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }

            let serial = parts[0]
            let stateStr = parts[1]
            let state: Device.DeviceState = switch stateStr {
            case "device": .online
            case "offline": .offline
            default: .unauthorized
            }

            var model = "Unknown"
            for part in parts.dropFirst(2) {
                if part.hasPrefix("model:") {
                    model = String(part.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    break
                }
            }

            let connectionType: Device.ConnectionType = serial.contains(".")
                ? .wireless : .usb

            var device = Device(id: serial, model: model, state: state,
                                  connectionType: connectionType)
            // 在线设备：从手机直接读厂家+市场名（优先用 getprop 的 model，比 adb 更准）
            if state == .online {
                let info = getDeviceInfo(device: serial)
                let mfr = info.manufacturer
                let mkt = info.marketName
                // getprop 的 model 更准确，覆盖 adb devices -l 的
                let propModel = info.model.trimmingCharacters(in: .whitespaces)
                if !propModel.isEmpty { device.model = propModel }
                if !mkt.isEmpty {
                    device.displayName = mkt
                } else if !mfr.isEmpty {
                    device.displayName = "\(mfr) \(device.model)"
                }
            }
            devices.append(device)
        }
        return devices
    }

    func connectWireless(ip: String, port: Int = C.adbPort) throws -> String {
        let result = try run(["connect", "\(ip):\(port)"], timeout: 10)
        // adb connect 失败时退出码仍为 0，需检查输出内容
        let lower = result.lowercased()
        if lower.contains("failed") || lower.contains("unable") || lower.contains("cannot") {
            throw ADBError.commandFailed(exitCode: -1, stderr: result.trimmingCharacters(in: .newlines))
        }
        return result
    }

    /// 从设备直接读取厂家和型号（比本地字典准，覆盖所有机型）
    func getDeviceInfo(device: String) -> (manufacturer: String, marketName: String, model: String) {
        let props = [
            "ro.product.manufacturer",
            "ro.product.marketname",
            "ro.product.model"
        ]
        var result: [String: String] = [:]
        for prop in props {
            let out: String
            do {
                out = try run(["-s", device, "shell", "getprop \(prop)"], timeout: 3)
                if out.isEmpty {
                    androidFMLog("[ADBService] getDeviceInfo: getprop \(prop) returned empty")
                }
            } catch {
                androidFMLog("[ADBService] getDeviceInfo: getprop \(prop) failed: \(error)")
                out = ""
            }
            result[prop] = out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if result.values.allSatisfy({ $0.isEmpty }) {
            androidFMLog("[ADBService] getDeviceInfo: all props failed for device \(device)")
        }
        return (
            manufacturer: result["ro.product.manufacturer"] ?? "",
            marketName: result["ro.product.marketname"] ?? "",
            model: result["ro.product.model"] ?? ""
        )
    }

    /// 把 USB 设备切到 TCP 模式（端口默认 5555），之后可拔线无线连
    func enableTCP(device: String, port: Int = C.adbPort) throws -> String {
        try run(["-s", device, "tcpip", "\(port)"])
    }

    /// 获取手机的 WiFi IP 地址（兼容多接口名，优先 WiFi）
    func getDeviceIP(device: String) throws -> String {
        // 方案 1: getprop 直接拿 DHCP 分配的 IP（最通用）
        var out = try run(["-s", device, "shell", "getprop dhcp.wlan0.ipaddress"])
        var ip = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ip.isEmpty { return ip }

        // 方案 2: ip addr 直接查 wlan0（最可靠）
        let wlanCmd = "ip -4 addr show wlan0 2>/dev/null | grep 'inet ' | grep -oE '([0-9]+\\.){3}[0-9]+' | head -1"
        out = (try? run(["-s", device, "shell", wlanCmd], timeout: 5)) ?? ""
        ip = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ip.isEmpty { return ip }

        // 方案 3: 过滤 WiFi 接口（wlan/wlp），排除移动数据和虚拟接口
        let wifiCmd = "ip -4 addr show 2>/dev/null | grep -E 'inet .* (wlan|wlp)' | grep -oE '([0-9]+\\.){3}[0-9]+' | head -1"
        out = (try? run(["-s", device, "shell", wifiCmd], timeout: 5)) ?? ""
        ip = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ip.isEmpty { return ip }

        // 方案 4: 最后兜底，排除常见非 WiFi 接口
        let fallbackCmd = "ip -4 addr show 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | grep -vE ' (rmnet|ccmni|rndis|dummy|sit|lo)' | grep -oE '([0-9]+\\.){3}[0-9]+' | head -1"
        out = (try? run(["-s", device, "shell", fallbackCmd], timeout: 5)) ?? ""
        ip = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return ip
    }

    func disconnectWireless(serial: String) throws -> String {
        try run(["disconnect", serial])
    }

    func getCurrentWiFiIP() -> String {
        // 使用 ifconfig 获取 en0 (WiFi) 接口的 IP
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        task.arguments = ["en0"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("inet ") {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 2 {
                    let ip = parts[1]
                    // 排除 127.x 回环地址
                    if !ip.hasPrefix("127.") {
                        return ip
                    }
                }
            }
        }
        return ""
    }

}