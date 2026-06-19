import SwiftUI
import AppKit

/// 缩略图缓存 —— NSCache 保证线程安全，解决数据竞争崩溃 (SIGSEGV)
@Observable
final class ThumbnailCache: @unchecked Sendable {
    private let cache = NSCache<NSString, NSImage>()
    private var loading: Set<String> = []
    private let loadingQueue = DispatchQueue(label: "thumbnail.loading")
    private let thumbnailQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 4
        q.qualityOfService = .utility
        return q
    }()

    init() {
        cache.countLimit = C.thumbnailCacheCountLimit
        cache.totalCostLimit = C.thumbnailCacheTotalCostLimit
    }

    func get(_ path: String) -> NSImage? {
        cache.object(forKey: path as NSString)
    }

    @MainActor
    func load(for file: FileItem, device: Device) {
        let ext = (file.name as NSString).pathExtension.lowercased()
        guard C.imageExts.contains(ext), get(file.path) == nil else { return }

        // 跳过大文件（>5MB），避免拉原图造成卡顿
        if file.size > 5 * 1024 * 1024 { return }

        var shouldSkip = false
        loadingQueue.sync {
            if loading.contains(file.path) { shouldSkip = true; return }
            loading.insert(file.path)
        }
        guard !shouldSkip else { return }
        let remotePath = file.path
        let deviceId = device.id
        let tmpPath = "\(C.tmpThumbPrefix)\(UUID().uuidString).\(ext)"
        let adbPath = ADBService.shared.adbPath
        let queue = thumbnailQueue

        Task.detached { [weak self] in
            defer {
                _ = self?.loadingQueue.sync {
                    self?.loading.remove(remotePath)
                }
            }
            defer {
                try? FileManager.default.removeItem(atPath: tmpPath)
            }

            // 用独立 OperationQueue 限流（maxConcurrent=4），不走 ADBService 串行队列
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                queue.addOperation {
                    defer { continuation.resume() }

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: adbPath)
                    process.arguments = ["-s", deviceId, "pull", remotePath, tmpPath]
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice
                    var environment = ProcessInfo.processInfo.environment
                    environment["LC_ALL"] = "en_US.UTF-8"
                    process.environment = environment

                    do {
                        try process.run()
                        process.waitUntilExit()
                        guard process.terminationStatus == 0 else { return }
                        guard let img = NSImage(contentsOfFile: tmpPath) else { return }
                        let thumb = img.resized(to: C.thumbnailSize)
                        let estimatedCost = Int(C.thumbnailSize.width * C.thumbnailSize.height * 4)
                        self?.cache.setObject(thumb, forKey: remotePath as NSString, cost: estimatedCost)
                    } catch {
                        androidFMLog("thumbnail load failed: \(error.localizedDescription)")
                    }
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
