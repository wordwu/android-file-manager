import SwiftUI
import Observation

@MainActor
@Observable
final class FileBrowser {
    private let adb = ADBService.shared

    @ObservationIgnored private let defaults = UserDefaults.standard

    var currentPath: String = UserDefaults.standard.string(forKey: "currentPath") ?? "/sdcard" {
        didSet { defaults.set(currentPath, forKey: "currentPath") }
    }
    var files: [FileItem] = [] {
        didSet { _sortDirty = true }
    }
    var selectedFile: FileItem?
    var selectedFiles: Set<FileItem> = []
    var isLoading = false
    var hasMore = false
    var pathStack: [String] = []

    // Set after init by the App
    var searchManager: SearchManager?

    var fileTypeFilter: FileTypeFilter = .all {
        didSet { if oldValue != fileTypeFilter { _sortDirty = true } }
    }

    // 排序
    enum SortOrder: String, CaseIterable {
        case nameAsc = "名称 ↑"
        case nameDesc = "名称 ↓"
        case sizeAsc = "大小 ↑"
        case sizeDesc = "大小 ↓"
        case dateAsc = "日期 ↑"
        case dateDesc = "日期 ↓"
    }

    enum FileTypeFilter: String, CaseIterable {
        case all = "全部"
        case image = "图片"
        case video = "视频"
        case audio = "音频"
        case document = "文档"
        case apk = "APK"

        var extensions: [String] {
            switch self {
            case .all: return []
            case .image: return Array(C.imageExts)
            case .video: return ["mp4", "mkv", "avi", "mov", "3gp", "flv", "webm"]
            case .audio: return ["mp3", "wav", "flac", "aac", "ogg", "m4a", "opus"]
            case .document: return ["pdf", "doc", "docx", "xls", "xlsx", "txt", "md", "ppt", "pptx"]
            case .apk: return ["apk"]
            }
        }
    }

    // 排序
    var sortOrder: SortOrder = {
        guard let raw = UserDefaults.standard.string(forKey: "sortOrder"),
              let order = SortOrder(rawValue: raw) else { return .nameAsc }
        return order
    }() {
        didSet {
            defaults.set(sortOrder.rawValue, forKey: "sortOrder")
            if oldValue != sortOrder { _sortDirty = true }
        }
    }

    // 操作反馈
    var statusMessage: String?

    // MARK: - 批量重命名

    enum RenameMode: String, CaseIterable {
        case prefix = "前缀"
        case suffix = "后缀"
        case replace = "替换"
        case numbering = "编号"
    }

    func renameSelected(device: String, mode: RenameMode, text: String) async -> Int {
        let paths = allSelectedPaths()
        guard !paths.isEmpty else { return 0 }

        androidFMLog("renameSelected: device=\(device) mode=\(mode.rawValue) text='\(text)' count=\(paths.count)")

        var renamed = 0
        var index = 1

        for path in paths {
            let name = (path as NSString).lastPathComponent
            // 跳过目录（mv 对目录通常失败，浪费 adb 调用且计数偏少）
            if let idx = files.firstIndex(where: { $0.path == path }), files[idx].isDirectory {
                androidFMLog("renameSelected: skipping directory '\(name)'")
                continue
            }
            let dir = (path as NSString).deletingLastPathComponent
            let ext = (name as NSString).pathExtension
            let baseName: String = if !ext.isEmpty {
                String(name.dropLast(ext.count + 1))
            } else {
                name
            }

            let newName: String
            switch mode {
            case .prefix:
                newName = "\(text)\(name)"
            case .suffix:
                if ext.isEmpty {
                    newName = "\(name)\(text)"
                } else {
                    newName = "\(baseName)\(text).\(ext)"
                }
            case .replace:
                newName = name.replacingOccurrences(of: text, with: "")
            case .numbering:
                if ext.isEmpty {
                    newName = "\(text)\(index)"
                } else {
                    newName = "\(text)\(index).\(ext)"
                }
                index += 1
            }

            guard newName != name, !newName.isEmpty else { continue }
            // 防御路径遍历：禁止 newName 含 / 或 ..
            guard !newName.contains("/"), !newName.contains("..") else {
                androidFMLog("renameSelected: blocked path traversal in '\(newName)'")
                continue
            }

            let newPath = "\(dir)/\(newName)"

            do {
                androidFMLog("rename: mv '\(path)' -> '\(newPath)'")
                try await Task { [adb, device, path, newPath] in
                    try adb.renameItem(device: device, from: path, to: newPath)
                }.value
                renamed += 1
                androidFMLog("rename: OK")
            } catch {
                androidFMLog("rename: FAILED \(path) -> \(newPath): \(error)")
            }
        }

        clearSelection()
        setStatus("已重命名 \(renamed) 项")
        androidFMLog("renameSelected: done, renamed=\(renamed)/\(paths.count)")

        await loadDirectory(device: device)

        return renamed
    }

    // MARK: - 排序后的文件列表（带缓存，避免 SwiftUI 重绘时重复排序）

    private var _sortedCache: [FileItem] = []
    private var _sortDirty = true

    // MARK: - 目录书签

    var bookmarks: [Bookmark] {
        get {
            guard let data = defaults.data(forKey: "bookmarks") else { return [] }
            do {
                return try JSONDecoder().decode([Bookmark].self, from: data)
            } catch {
                androidFMLog("书签解码失败: \(error.localizedDescription)")
                return []
            }
        }
        set {
            do {
                let data = try JSONEncoder().encode(newValue)
                defaults.set(data, forKey: "bookmarks")
            } catch {
                androidFMLog("书签编码失败: \(error.localizedDescription)")
            }
        }
    }

    struct Bookmark: Codable, Identifiable, Hashable {
        var id = UUID()
        let name: String
        let path: String
    }

    func addBookmark(name: String, path: String) {
        var bm = bookmarks
        if !bm.contains(where: { $0.path == path }) {
            bm.append(Bookmark(name: name, path: path))
            bookmarks = bm
            setStatus("已添加书签：\(name)")
        }
    }

    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks = bookmarks.filter { $0.id != bookmark.id }
        setStatus("已移除书签")
    }

    var sortedFiles: [FileItem] {
        if _sortDirty {
            let filtered = fileTypeFilter == .all ? files : files.filter { f in
                let ext = (f.name as NSString).pathExtension.lowercased()
                return f.isDirectory || fileTypeFilter.extensions.contains(ext)
            }
            _sortedCache = filtered.sorted { a, b in
            // 文件夹始终在前
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            switch sortOrder {
            case .nameAsc:  return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .nameDesc: return a.name.localizedStandardCompare(b.name) == .orderedDescending
            case .sizeAsc:  return a.size < b.size
            case .sizeDesc: return a.size > b.size
            case .dateAsc:
                let da = a.modifiedDate ?? .distantPast
                let db = b.modifiedDate ?? .distantPast
                return da < db
            case .dateDesc:
                let da = a.modifiedDate ?? .distantPast
                let db = b.modifiedDate ?? .distantPast
                return da > db
            }
            }
            _sortDirty = false
        }
        return _sortedCache
    }

    // MARK: - 目录加载

    func loadDirectory(device: String, path: String? = nil) async {
        if let path { currentPath = path }
        androidFMLog("FileBrowser.loadDirectory: device=\(device) path=\(currentPath)")
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await Task { [adb, path = currentPath, device] in
                try adb.listFiles(device: device, path: path, maxCount: 500, skip: 0)
            }.value
            androidFMLog("FileBrowser.loadDirectory: got \(result.count) files")
            files = result
            hasMore = result.count == 500
            _sortDirty = true
            statusMessage = nil
        } catch {
            androidFMLog("FileBrowser.loadDirectory ERROR: \(error)")
            let errStr = error.localizedDescription
            if errStr.contains("Permission denied") || errStr.contains("权限") {
                setStatus("权限不足，无法访问此目录")
            } else {
                setStatus(errStr)
            }
            files = []
            _sortDirty = true
        }
    }

    // MARK: - 分页加载

    func loadMore(device: String) async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await Task { [adb, path = currentPath, device] in
                try adb.listFiles(device: device, path: path, maxCount: 500, skip: files.count)
            }.value
            androidFMLog("FileBrowser.loadMore: got \(result.count) files, total=\(files.count + result.count)")
            files.append(contentsOf: result)
            hasMore = result.count == 500
            _sortDirty = true
        } catch {
            androidFMLog("FileBrowser.loadMore ERROR: \(error)")
            setStatus("加载更多失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 选择

    var selectionCount: Int {
        if !selectedFiles.isEmpty { return selectedFiles.count }
        if selectedFile != nil { return 1 }
        return 0
    }

    func toggleSelection(_ item: FileItem) {
        if selectedFiles.contains(item) {
            selectedFiles.remove(item)
        } else {
            selectedFiles.insert(item)
        }
        if selectedFiles.isEmpty { selectedFile = nil }
    }

    func clearSelection() {
        selectedFile = nil
        selectedFiles.removeAll()
    }

    func allSelectedPaths() -> [String] {
        if !selectedFiles.isEmpty { return selectedFiles.map(\.path) }
        if let file = selectedFile { return [file.path] }
        return []
    }

    // MARK: - 删除

    func deleteSelected(device: String) async {
        let paths = allSelectedPaths()
        guard !paths.isEmpty else { return }
        var deleted = 0
        var failed = 0
        for path in paths {
            do {
                try await Task { [adb] in
                    try adb.deleteItem(device: device, path: path)
                }.value
                deleted += 1
            } catch {
                androidFMLog("delete failed: \(path): \(error)")
                failed += 1
            }
        }
        clearSelection()
        if failed > 0 {
            setStatus("已删除 \(deleted) 项，\(failed) 项失败")
        } else {
            setStatus("已删除 \(deleted) 项")
        }
    }

    // MARK: - 导航

    func navigateInto(_ item: FileItem) {
        guard item.isDirectory else { return }
         searchManager?.clearSearch()
        pathStack.append(currentPath)
        currentPath = item.path
        clearSelection()
    }

    func navigateBack() {
        guard !pathStack.isEmpty else { return }
        searchManager?.clearSearch()
        currentPath = pathStack.removeLast()
    }

    func navigateUp() {
        guard currentPath != "/" else { return }
        searchManager?.clearSearch()
        let parent = (currentPath as NSString).deletingLastPathComponent
        if pathStack.last == parent {
            _ = pathStack.popLast()
        } else {
            pathStack.append(currentPath)
        }
        currentPath = parent
    }

    func navigateTo(path: String) {
        searchManager?.clearSearch()
        pathStack.append(currentPath)
        currentPath = path
        if let idx = pathStack.firstIndex(of: path) {
            pathStack.removeSubrange(idx...)
        }
    }

    func goHome(device: String) async {
        pathStack.removeAll()
        let candidates = ["/sdcard", "/storage/emulated/0"]
        var lastError: String?
        for (i, path) in candidates.enumerated() {
            await loadDirectory(device: device, path: path)
            if !files.isEmpty && statusMessage == nil { return }
            if let msg = statusMessage { lastError = msg }
            if i == candidates.count - 1 { break }
            androidFMLog("goHome: \(path) 返回空，尝试下一候选")
        }
        if files.isEmpty {
            setStatus(lastError ?? "无法访问存储目录")
        }
    }

    func refresh(device: String) async {
        await loadDirectory(device: device)
    }

    // MARK: - 状态提示

    private var dismissTask: Task<Void, Never>?

    func setStatus(_ msg: String) {
        dismissTask?.cancel()
        statusMessage = msg
        let captured = msg
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(C.statusMessageTTL))
            if statusMessage == captured { statusMessage = nil }
        }
    }
}