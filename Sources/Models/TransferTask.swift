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
    var progress: Double { totalBytes > 0 ? Double(transferredBytes) / Double(totalBytes) : 0 }
    var status: Status = .queued

    enum Direction { case push, pull }
    enum Status: String {
        case queued = "排队中"
        case transferring = "传输中"
        case completed = "已完成"
        case failed = "失败"
    }
}
