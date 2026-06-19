import Foundation
import Observation

@MainActor
@Observable
final class AppListViewModel {
    var apps: [AppInfo] = [] {
        didSet { _filterDirty = true }
    }
    var isLoading = false
    var error: String?
    var statusMessage: String?
    var filterText = "" {
        didSet { _filterDirty = true }
    }
    var showSystemApps = false {
        didSet { _filterDirty = true }
    }
    
    private let adb = ADBService.shared
    
    private var _filteredCache: [AppInfo] = []
    private var _filterDirty = true
    
    /// 过滤后的应用列表
    var filteredApps: [AppInfo] {
        if _filterDirty {
            var result = apps
            if !showSystemApps {
                result = result.filter { !$0.isSystem }
            }
            if !filterText.isEmpty {
                let q = filterText.lowercased()
                result = result.filter {
                    $0.displayName.lowercased().contains(q) ||
                    $0.packageName.lowercased().contains(q)
                }
            }
            _filteredCache = result.sorted { a, b in
                if a.isSystem != b.isSystem {
                    return !a.isSystem // 三方应用在前
                }
                return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
            }
            _filterDirty = false
        }
        return _filteredCache
    }
    
    var systemCount: Int { apps.filter(\.isSystem).count }
    
    func loadApps(device: String) async {
            isLoading = true
            error = nil
            do {
                apps = try await Task { [adb] in
                    try adb.listPackages(device: device)
                }.value
                androidFMLog("appList: loaded \\(apps.count) apps (\\(apps.filter { !$0.isSystem }.count) third-party)")
                let tp = apps.filter { !$0.isSystem }
                for app in tp.prefix(5) {
                    androidFMLog("appList: diag \(app.packageName) displayName='\(app.displayName)' resolved=\(String(describing: app.resolvedName))")
                }
            
                // 后台逐个解析三方应用名称和图标
                resolveNamesInBackground(device: device)
            } catch {
                self.error = error.localizedDescription
                androidFMLog("appList: error \\(error.localizedDescription)")
            }
            isLoading = false
        }
    
    func uninstall(_ app: AppInfo, device: String) async {
        do {
            let result = try await Task { [adb] in
                try adb.uninstallPackage(device: device, package: app.packageName)
            }.value
            apps.removeAll { $0.packageName == app.packageName }
            statusMessage = "已卸载 \(app.displayName)"
        } catch {
            statusMessage = "卸载失败：\(error.localizedDescription)"
        }
    }
    
    /// 导出 APK 到 ~/Downloads
    func exportAPK(_ app: AppInfo, device: String) async {
        do {
            let dest = try await Task { [adb] in
                try await adb.pullAPK(
                    device: device,
                    package: app.packageName,
                    apkPath: app.apkPath,
                    toLocalDir: NSHomeDirectory() + "/Downloads"
                ) { _, _ in }
            }.value
            statusMessage = "已导出：\(dest)"
            androidFMLog("appList: exported \(app.packageName) → \(dest)")
        } catch {
            statusMessage = "导出失败：\(error.localizedDescription)"
        }
    }
    
    private var resolveTask: Task<Void, Never>?
    
    /// 后台逐个解析三方应用名称和图标
    private func resolveNamesInBackground(device: String) {
        resolveTask?.cancel()
        resolveTask = Task(priority: .background) { [weak self, adb] in
            guard let self = self else { return }
            let thirdParty = await MainActor.run { self.apps.filter { !$0.isSystem } }
            androidFMLog("appList: resolving names for \\(thirdParty.count) third-party apps")
            for app in thirdParty {
                // 已有名称或图标则跳过
                let hasName = await MainActor.run { app.resolvedName != nil }
                if hasName { continue }
                
                if let meta = await adb.resolveAppMeta(device: device, package: app.packageName, apkPath: app.apkPath) {
                    androidFMLog("appList: resolved \\(app.packageName) → '\\(meta.name)'")
                    await MainActor.run {
                        if self.apps.firstIndex(where: { $0.id == app.id }) != nil {
                            var apps = self.apps
                            if let idx = apps.firstIndex(where: { $0.id == app.id }) {
                                apps[idx].resolvedName = meta.name
                                apps[idx].iconPath = meta.iconPath
                            }
                            self.apps = apps
                        }
                    }
                }
            }
        }
    }
}
