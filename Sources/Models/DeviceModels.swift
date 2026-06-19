import Foundation
import SwiftUI

// MARK: - 电池

struct BatteryInfo {
    let level: Int                // 0-100
    let health: String            // 良好/过热/损坏/过压
    let status: String            // 充电中/放电中/未充电/已充满
    let temperature: Double       // 摄氏度
    let technology: String        // Li-ion / Li-poly
    
    var levelText: String { "\(level)%" }
    var tempText: String { String(format: "%.1f°C", temperature) }
    var levelColor: Color {
        if level >= 80 { return .green }
        if level >= 30 { return .yellow }
        return .red
    }
}

// MARK: - 存储

struct StorageInfo {
    let totalBytes: Int64
    let usedBytes: Int64
    
    var freeBytes: Int64 { totalBytes - usedBytes }
    var totalText: String { formatBytes(totalBytes) }
    var usedText: String { formatBytes(usedBytes) }
    var freeText: String { formatBytes(freeBytes) }
    var usagePercent: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100 : 0 }
    
    private func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1_073_741_824 { return String(format: "%.1f GB", Double(bytes) / 1_073_741_824) }
        if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        return "\(bytes / 1024) KB"
    }
}

// MARK: - 系统

struct SystemInfo {
    let model: String
    let manufacturer: String
    let androidVersion: String
    let sdkVersion: String
    let serialNo: String
    let buildNumber: String
    
    var modelText: String { model.isEmpty ? "未知" : model }
    var manufacturerText: String { manufacturer.isEmpty ? "未知" : manufacturer }
    var versionText: String { "Android \(androidVersion) (SDK \(sdkVersion))" }
}

// MARK: - 设备完整信息

struct DeviceInfo {
    let battery: BatteryInfo
    let storage: StorageInfo
    let system: SystemInfo
}

// MARK: - 通话记录

enum CallType {
    case incoming, outgoing, missed, rejected, other
    
    var label: String {
        switch self {
        case .incoming: return "来电"
        case .outgoing: return "去电"
        case .missed: return "未接"
        case .rejected: return "拒接"
        case .other: return "其他"
        }
    }
    
    var iconName: String {
        switch self {
        case .incoming: return "phone.arrow.down.left"
        case .outgoing: return "phone.arrow.up.right"
        case .missed: return "phone.arrow.down.left"
        case .rejected: return "phone.down"
        case .other: return "phone"
        }
    }
    
    var color: Color {
        switch self {
        case .incoming: return .blue
        case .outgoing: return .green
        case .missed: return .red
        case .rejected: return .orange
        case .other: return .gray
        }
    }
}

struct CallLogItem: Identifiable {
    let id: UUID
    let phoneNumber: String
    let date: Date
    let duration: Int64    // 秒
    let type: CallType
}
