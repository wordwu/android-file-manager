import AppKit

enum PreviewLoader {
    /// 从设备拉取图片并返回 NSImage
    static func loadImage(from remotePath: String, deviceId: String, ext: String) async throws -> NSImage {
        let tmpPath = "\(C.tmpPreviewPrefix)\(UUID().uuidString).\(ext)"
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }
        try await ADBService.shared.pullFile(device: deviceId, remotePath: remotePath, localPath: tmpPath) { _, _ in }
        guard let img = NSImage(contentsOfFile: tmpPath) else {
            throw NSError(domain: "PreviewLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法加载图片"])
        }
        return img
    }
}
