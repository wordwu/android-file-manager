import SwiftUI
import Observation

@MainActor
@Observable
final class ClipboardManager {
    private let adb = ADBService.shared

    var clipboard: [String] = []
    var clipboardOperation: ClipboardOp = .copy

    enum ClipboardOp {
        case copy, cut
    }

    // Set after init by the App
    var fileBrowser: FileBrowser?

    // MARK: - 剪贴板操作

    func copySelected(paths: [String]) {
        guard !paths.isEmpty else { return }
        clipboard = paths
        clipboardOperation = .copy
        fileBrowser?.setStatus("已复制 \(paths.count) 项")
    }

    func cutSelected(paths: [String]) {
        guard !paths.isEmpty else { return }
        clipboard = paths
        clipboardOperation = .cut
        fileBrowser?.setStatus("已剪切 \(paths.count) 项")
    }

    func paste(to destDir: String, device: String) async {
        guard let browser = fileBrowser else { return }
        let items = clipboard
        let op = clipboardOperation
        guard !items.isEmpty else { return }

        // Step 1: Resolve name conflicts and build paste plan
        let plan = await resolvePasteConflicts(
            clipboard: items, destDir: destDir, device: device,
            operation: op, browser: browser
        )

        // Step 2: Execute paste for non-skipped items
        let toPaste = plan.filter { !$0.skipped }.map { (src: $0.src, dest: $0.dest) }
        let pasted = await executePaste(items: toPaste, device: device, operation: op)

        // Step 3: Clean up clipboard after cut
        if op == .cut {
            var existingPaths = Set(browser.files.map { $0.path })
            if destDir == browser.currentPath {
                existingPaths.subtract(items)
            }
            if destDir != browser.currentPath {
                if let targetFiles = try? await Task(operation: { [adb, device, destDir] () -> [FileItem] in
                    try adb.listFiles(device: device, path: destDir)
                }).value {
                    existingPaths.formUnion(targetFiles.map { $0.path })
                }
            }
            for item in toPaste {
                existingPaths.insert(item.dest)
            }
            cleanupClipboardAfterCut(destDir: destDir, pastedPaths: existingPaths, browser: browser)
        }

        // Step 4: Final status message
        let autoNumbered = plan.filter { item in
            guard !item.skipped else { return false }
            let srcName = (item.src as NSString).lastPathComponent
            let destName = (item.dest as NSString).lastPathComponent
            return srcName != destName
        }.count

        if autoNumbered > 0 {
            browser.setStatus("已粘贴 \(pasted) 项，\(autoNumbered) 项重名已自动编号")
        } else {
            browser.setStatus("已粘贴 \(pasted) 项")
        }
    }

    // MARK: - Paste helpers

    /// Resolves name conflicts for clipboard items against target directory.
    /// Handles same-dir CUT dedup, cross-dir target file merge, system-dir blocking,
    /// and name-collision auto-numbering (up to counter 99).
    /// Returns a list of (source path, destination path, whether skipped).
    private func resolvePasteConflicts(
        clipboard: [String], destDir: String, device: String,
        operation: ClipboardOp, browser: FileBrowser
    ) async -> [(src: String, dest: String, skipped: Bool)] {
        let dest = destDir.hasSuffix("/") ? destDir : "\(destDir)/"
        var existingPaths = Set(browser.files.map { $0.path })

        // CUT 到同目录时排除源文件自身，避免 mv A -> A 1
        if operation == .cut && destDir == browser.currentPath {
            existingPaths.subtract(clipboard)
        }

        // 跨目录粘贴时，额外合并目标目录已有文件
        if destDir != browser.currentPath {
            if let targetFiles = try? await Task(operation: { [adb, device, destDir] () -> [FileItem] in
                try adb.listFiles(device: device, path: destDir)
            }).value {
                existingPaths.formUnion(targetFiles.map { $0.path })
            }
        }

        var result: [(src: String, dest: String, skipped: Bool)] = []

        for srcPath in clipboard {
            let name = (srcPath as NSString).lastPathComponent
            var destPath = "\(dest)\(name)"
            var skipped = false

            // 禁止写入系统目录
            if C.systemDirPrefixes.contains(where: { destPath.hasPrefix($0) }) {
                browser.setStatus("禁止写入系统目录")
                androidFMLog("paste blocked: dest \(destPath) is in system dir")
                skipped = true
            }

            if !skipped && existingPaths.contains(destPath) {
                let base = destPath
                var counter = 1
                while existingPaths.contains(destPath) {
                    let dotIdx = base.lastIndex(of: ".")
                    if let idx = dotIdx {
                        destPath = "\(base[..<idx]) \(counter)\(base[idx...])"
                    } else {
                        destPath = "\(base) \(counter)"
                    }
                    counter += 1
                    if counter > 99 {
                        browser.setStatus("跳过 \(name): 文件名冲突过多")
                        skipped = true
                        break
                    }
                }
            }

            result.append((src: srcPath, dest: destPath, skipped: skipped))
            if !skipped {
                existingPaths.insert(destPath)
            }
        }

        return result
    }

    /// Executes mv (cut) or cp (copy) for each item in the list.
    /// Returns the count of successfully pasted items.
    private func executePaste(
        items: [(src: String, dest: String)], device: String, operation: ClipboardOp
    ) async -> Int {
        var pasted = 0
        let total = clipboard.count

        for (index, item) in items.enumerated() {
            do {
                if operation == .cut {
                    try await Task { [adb, device] in
                        try adb.renameItem(device: device, from: item.src, to: item.dest)
                    }.value
                } else {
                    let escapedSrc = ADBService.shared.shellEscape(item.src)
                    let escapedDst = ADBService.shared.shellEscape(item.dest)
                    try await Task { [adb, device] in
                        _ = try adb.shell(device: device, command: "cp -r \"\(escapedSrc)\" \"\(escapedDst)\"")
                    }.value
                }
                pasted += 1
            } catch {
                androidFMLog("paste failed: \(item.src) -> \(item.dest): \(error)")
            }

            let processed = index + 1
            if processed < total {
                fileBrowser?.setStatus("正在粘贴 \(processed)/\(total)...")
            }
        }

        return pasted
    }

    /// Removes successfully-moved items from clipboard after a cut operation.
    /// Items whose destination exists in `pastedPaths` are filtered out.
    private func cleanupClipboardAfterCut(
        destDir: String, pastedPaths: Set<String>, browser: FileBrowser
    ) {
        let dest = destDir.hasSuffix("/") ? destDir : "\(destDir)/"
        clipboard = clipboard.filter { src in
            let name = (src as NSString).lastPathComponent
            let moved = "\(dest)\(name)"
            return !pastedPaths.contains(moved)
        }
        if !clipboard.isEmpty {
            browser.setStatus("\(clipboard.count) 项未完成，可重试")
        }
    }
}
