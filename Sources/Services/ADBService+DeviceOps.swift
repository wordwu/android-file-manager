import Foundation

extension ADBService {
    // MARK: - APK 导出
    
    func pullAPK(device: String, package: String, apkPath: String, toLocalDir: String,
                 progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> String {
        let fileName = "\(package).apk"
        let dest = "\(toLocalDir)/\(fileName)"
        try await pullFile(device: device, remotePath: apkPath, localPath: dest, progress: progress)
        return dest
    }
    
    // MARK: - 设备信息
    
    func getFullDeviceInfo(device: String) throws -> DeviceInfo {
        let batteryRaw = try? run(["-s", device, "shell", "dumpsys battery"], timeout: 8)
        let battery = Self.parseBattery(batteryRaw ?? "")
        
        let storageRaw = try? run(["-s", device, "shell", "df -h /data 2>/dev/null; df -h /sdcard 2>/dev/null"], timeout: 8)
        let storage = Self.parseStorage(storageRaw ?? "")
        
        let keys = ["ro.product.model", "ro.product.manufacturer", "ro.build.version.release",
                    "ro.build.version.sdk", "ro.serialno", "ro.build.display.id"]
        let cmd = keys.map { "getprop \($0) 2>/dev/null" }.joined(separator: "; echo '---'; ")
        let propRaw = (try? run(["-s", device, "shell", cmd], timeout: 8)) ?? ""
        let sys = Self.parseSystemProps(propRaw, keys: keys)
        
        return DeviceInfo(battery: battery, storage: storage, system: sys)
    }
    
    private static func parseBattery(_ raw: String) -> BatteryInfo {
        var level = 0, health = "未知", status = "未知", temp = 0.0, tech = ""
        for line in raw.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("level:") { level = Int(t.replacingOccurrences(of: "level:", with: "").trimmingCharacters(in: .whitespaces)) ?? 0 }
            if t.hasPrefix("health:") {
                let v = t.replacingOccurrences(of: "health:", with: "").trimmingCharacters(in: .whitespaces)
                health = v == "2" ? "良好" : v == "3" ? "过热" : v == "4" ? "损坏" : v == "5" ? "过压" : "未知(\(v))"
            }
            if t.hasPrefix("status:") {
                let v = t.replacingOccurrences(of: "status:", with: "").trimmingCharacters(in: .whitespaces)
                status = v == "2" ? "充电中" : v == "3" ? "放电中" : v == "4" ? "未充电" : v == "5" ? "已充满" : "未知(\(v))"
            }
            if t.hasPrefix("temperature:") { temp = (Double(t.replacingOccurrences(of: "temperature:", with: "").trimmingCharacters(in: .whitespaces)) ?? 0) / 10.0 }
            if t.hasPrefix("technology:") { tech = t.replacingOccurrences(of: "technology:", with: "").trimmingCharacters(in: .whitespaces) }
        }
        return BatteryInfo(level: level, health: health, status: status, temperature: temp, technology: tech)
    }
    
    private static func parseStorage(_ raw: String) -> StorageInfo {
        var total: Int64 = 0, used: Int64 = 0
        for line in raw.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            let parts = t.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 6, parts[5] == "/data" || parts[5] == "/sdcard" || parts[5] == "/storage/emulated" else { continue }
            if let tv = parseSizeHuman(parts[1]) { total += tv }
            if let uv = parseSizeHuman(parts[2]) { used += uv }
        }
        return StorageInfo(totalBytes: total, usedBytes: used)
    }
    
    private static func parseSizeHuman(_ s: String) -> Int64? {
        let u = s.uppercased()
        if u.hasSuffix("G") { return Int64((Double(u.dropLast()) ?? 0) * 1024 * 1024 * 1024) }
        if u.hasSuffix("M") { return Int64((Double(u.dropLast()) ?? 0) * 1024 * 1024) }
        if u.hasSuffix("K") { return Int64((Double(u.dropLast()) ?? 0) * 1024) }
        return Int64(s)
    }
    
    private static func parseSystemProps(_ raw: String, keys: [String]) -> SystemInfo {
        let blocks = raw.components(separatedBy: "---")
        let values = blocks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var model = "", manufacturer = "", release = "", sdk = "", serial = "", build = ""
        for (i, key) in keys.enumerated() {
            guard i < values.count else { continue }
            switch key {
            case "ro.product.model": model = values[i]
            case "ro.product.manufacturer": manufacturer = values[i]
            case "ro.build.version.release": release = values[i]
            case "ro.build.version.sdk": sdk = values[i]
            case "ro.serialno": serial = values[i]
            case "ro.build.display.id": build = values[i]
            default: break
            }
        }
        return SystemInfo(model: model, manufacturer: manufacturer, androidVersion: release, sdkVersion: sdk, serialNo: serial, buildNumber: build)
    }
    
    // MARK: - 通话记录
    
    /// 获取通话记录 — 多 URI 回退，覆盖主流手机厂商
    func getCallLogs(device: String) throws -> [CallLogItem] {
        // 不同厂商的 Content URI，按兼容性排序
        let uris = [
            "content://call_log/calls",                          // AOSP / 小米 / 一加 / 原生
            "content://com.android.contacts/calls",              // 部分三星 / LG
            "content://com.android.dialer/calllog",              // Google Dialer
        ]
        
        var lastError: String = ""
        for uri in uris {
            let cmd = "content query --uri \(uri) --projection number:date:duration:type"
            if let raw = try? run(["-s", device, "shell", cmd], timeout: 10),
               !raw.contains("Error") && !raw.contains("Permission") && !raw.contains("Unable to resolve") {
                let items = Self.parseCallLogs(raw)
                if !items.isEmpty {
                    androidFMLog("callLog via \(uri): \(items.count) entries")
                    return items
                }
            }
        }
        
        // 所有 URI 都失败，返回空结果并记录
        androidFMLog("callLog ALL URIs failed, last URI tried: \(uris.last ?? "")")
        return []
    }
    
    /// content query 输出格式：Row: 0 number=10016, date=1742278911955, duration=42, type=1
    private static func parseCallLogs(_ raw: String) -> [CallLogItem] {
        var items: [CallLogItem] = []
        
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.hasPrefix("Row:") else { continue }
            
            // "Row: 0 number=10016, date=..., duration=..., type=..."
            // 先找到第二个空格（Row 号后面），从那之后才是键值对
            guard let firstSpace = trimmed.firstIndex(of: " ") else { continue }
            let afterRow = String(trimmed[trimmed.index(after: firstSpace)...])
            // afterRow = "0 number=10016, date=..."
            guard let secondSpace = afterRow.firstIndex(of: " ") else { continue }
            let content = String(afterRow[afterRow.index(after: secondSpace)...]).trimmingCharacters(in: .whitespaces)
            // content = "number=10016, date=..., duration=..., type=..."
            
            let pairs = content.components(separatedBy: ",")
            var dict: [String: String] = [:]
            for pair in pairs {
                let kv = pair.trimmingCharacters(in: .whitespaces)
                let parts = kv.components(separatedBy: "=")
                if parts.count >= 2 {
                    dict[parts[0]] = parts.dropFirst().joined(separator: "=")
                }
            }
            
            if let item = callLogFromDict(dict) {
                items.append(item)
            }
        }
        return items
    }
    
    private static func callLogFromDict(_ dict: [String: String]) -> CallLogItem? {
        guard let number = dict["number"] else { return nil }
        let dateMs = Double(dict["date"] ?? "0") ?? 0
        let date = Date(timeIntervalSince1970: dateMs / 1000.0)
        let duration = Int64(dict["duration"] ?? "0") ?? 0
        let typeRaw = Int(dict["type"] ?? "0") ?? 0
        let type: CallType = switch typeRaw {
        case 1: .incoming
        case 2: .outgoing
        case 3: .missed
        case 5: .rejected
        default: .other
        }
        return CallLogItem(id: UUID(), phoneNumber: number, date: date, duration: duration, type: type)
    }
}
