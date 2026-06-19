import SwiftUI
import Observation

@MainActor
@Observable
final class SearchManager {
    private let adb = ADBService.shared

    var isSearching = false
    var searchQuery = ""

    // Set after init by the App
    var fileBrowser: FileBrowser?

    // MARK: - 搜索

    func search(device: String, query: String, currentPath: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let browser = fileBrowser else { return }
        isSearching = true
        searchQuery = query
        browser.isLoading = true
        defer { browser.isLoading = false }
        do {
            let searchPath = currentPath.hasSuffix("/") ? currentPath : "\(currentPath)/"
            androidFMLog("search: query=\(query) path=\(searchPath)")
            let output = try await Task { [adb] in
                try adb.searchFiles(device: device, query: query, from: searchPath)
            }.value
            androidFMLog("search: got \(output.components(separatedBy: "\n").count) lines")
            let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
            browser.files = lines.compactMap { line -> FileItem? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                let parts = trimmed.components(separatedBy: "|")
                guard parts.count >= 3 else { return nil }
                let isDir = parts[0] == "d"
                let filePath = parts[1..<(parts.count - 1)].joined(separator: "|")
                let size = Int64(parts[parts.count - 1]) ?? 0
                let name = (filePath as NSString).lastPathComponent
                return FileItem(
                    name: name,
                    path: filePath,
                    isDirectory: isDir,
                    size: size,
                    permissions: "",
                    modifiedDate: nil
                )
            }
            browser.setStatus("搜索 \"\(query)\": \(browser.files.count) 个结果")
        } catch {
            androidFMLog("search error: \(error)")
            browser.files = []
        }
    }

    func clearSearch() {
        isSearching = false
        searchQuery = ""
    }
}
