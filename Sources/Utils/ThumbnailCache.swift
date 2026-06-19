import SwiftUI
import AppKit

/// 缩略图缓存 —— NSCache 保证线程安全，解决数据竞争崩溃 (SIGSEGV)
@Observable
final class ThumbnailCache: @unchecked Sendable {
    private let cache = NSCache<NSString, NSImage>()
    private var loading: Set<String> = []
    private let loadingQueue = DispatchQueue(label: "thumbnail.loading")

    init() {
        cache.countLimit = C.thumbnailCacheCountLimit
        cache.totalCostLimit = C.thumbnailCacheTotalCostLimit
    }

    func get(_ path: String) -> NSImage? {
        cache.object(forKey: path as NSString)
    }

    func load(for file: FileItem, device: Device) {
        let ext = (file.name as NSString).pathExtension.lowercased()
        guard C.imageExts.contains(ext), get(file.path) == nil else { return }

        var shouldSkip = false
        loadingQueue.sync {
            if loading.contains(file.path) { shouldSkip = true; return }
            loading.insert(file.path)
        }
        guard !shouldSkip else { return }
        let remotePath = file.path
        let deviceId = device.id
        let tmpPath = "\(C.tmpThumbPrefix)\(UUID().uuidString).\(ext)"

        Task.detached { [weak self] in
            // Always clean up loading state
            defer {
                _ = self?.loadingQueue.sync {
                    self?.loading.remove(remotePath)
                }
            }
            // Always clean up temp file
            defer {
                do {
                    try FileManager.default.removeItem(atPath: tmpPath)
                } catch {
                    androidFMLog("thumbnail temp cleanup failed: \(error.localizedDescription)")
                }
            }
            do {
                try await ADBService.shared.pullFile(
                    device: deviceId,
                    remotePath: remotePath,
                    localPath: tmpPath
                ) { _, _ in }
                guard let img = NSImage(contentsOfFile: tmpPath) else { return }
                let thumb = img.resized(to: C.thumbnailSize)
                // cost = 估算内存字节数 (RGBA 4 bytes × width × height)
                let estimatedCost = Int(C.thumbnailSize.width * C.thumbnailSize.height * 4)
                self?.cache.setObject(thumb, forKey: remotePath as NSString, cost: estimatedCost)
            } catch {
                androidFMLog("thumbnail load failed: \(error.localizedDescription)")
                // Secondary cleanup: ensure temp file is removed even if defer is skipped
                do {
                    try FileManager.default.removeItem(atPath: tmpPath)
                } catch {
                    androidFMLog("thumbnail temp cleanup (catch) failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func clear() {
        cache.removeAllObjects()
        loadingQueue.sync { loading.removeAll() }
    }
}

// MARK: - NSImage 缩略图

extension NSImage {
    func resized(to size: NSSize) -> NSImage {
        let newImg = NSImage(size: size)
        newImg.lockFocus()
        draw(in: NSRect(origin: .zero, size: size),
             from: NSRect(origin: .zero, size: self.size),
             operation: .copy, fraction: 1.0)
        newImg.unlockFocus()
        return newImg
    }
}
