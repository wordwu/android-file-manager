import SwiftUI

struct BackupAppView: View {
    let device: Device
    @Environment(\.dismiss) private var dismiss

    @State private var apps: [AppInfo] = []
    @State private var selectedIds: Set<String> = []
    @State private var isLoading = true
    @State private var isBackingUp = false
    @State private var progress = (current: 0, total: 0)
    @State private var currentApp = ""
    @State private var result: (success: Int, failed: Int, dir: String)?
    @State private var filterText = ""
    @State private var selectAll = true

    private var filteredApps: [AppInfo] {
        if filterText.isEmpty { return apps }
        let q = filterText.lowercased()
        return apps.filter {
            $0.displayName.lowercased().contains(q) || $0.packageName.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏
            HStack {
                Text(isBackingUp ? "正在备份…" : "选择要备份的应用")
                    .font(.headline)
                Spacer()
                if !isBackingUp {
                    Button(selectAll ? "取消全选" : "全选") {
                        selectAll.toggle()
                        if selectAll {
                            selectedIds = Set(filteredApps.map(\.packageName))
                        } else {
                            selectedIds = []
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .padding(.trailing, 8)
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(isBackingUp)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // 搜索
            if !isBackingUp && !apps.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    TextField("搜索应用…", text: $filterText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }

            if isLoading {
                Spacer()
                ProgressView().scaleEffect(0.8)
                Text("正在读取应用列表…").font(.caption).foregroundColor(.secondary)
                Spacer()
            } else if isBackingUp {
                backupProgressView
            } else if result != nil {
                resultView
            } else {
                appListView
            }
        }
        .frame(minWidth: 420, idealWidth: 480, minHeight: 400, idealHeight: 560)
        .task {
            await loadApps()
        }
    }

    // MARK: - 应用列表

    private var appListView: some View {
        VStack(spacing: 0) {
            // 计数
            HStack {
                Text("已选 \(selectedIds.count) / \(filteredApps.count) 个")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            // 列表
            List(filteredApps) { app in
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { selectedIds.contains(app.packageName) },
                        set: { checked in
                            if checked {
                                selectedIds.insert(app.packageName)
                            } else {
                                selectedIds.remove(app.packageName)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.displayName)
                            .font(.body)
                            .lineLimit(1)
                        Text(app.packageName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)

            // 底部按钮
            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("开始备份 (\(selectedIds.count))") {
                    startBackup()
                }
                .disabled(selectedIds.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    // MARK: - 备份进度

    private var backupProgressView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView(value: Double(progress.current), total: Double(progress.total))
                .padding(.horizontal, 32)
            Text("\(progress.current) / \(progress.total)")
                .font(.caption)
                .foregroundColor(.secondary)
            if !currentApp.isEmpty {
                Text(currentApp)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
    }

    // MARK: - 结果

    private var resultView: some View {
        VStack(spacing: 12) {
            Spacer()
            if let r = result {
                Image(systemName: r.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(r.failed == 0 ? .green : .orange)
                Text("备份完成")
                    .font(.headline)
                Text("成功 \(r.success) 个，失败 \(r.failed) 个")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(r.dir)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            HStack {
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - 数据加载

    private func loadApps() async {
        do {
            let all = try await Task {
                try ADBService.shared.listPackages(device: device.id)
            }.value
            let thirdParty = all.filter { !$0.isSystem }
            apps = thirdParty.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            selectedIds = Set(thirdParty.map(\.packageName))
        } catch {
            apps = []
        }
        isLoading = false
    }

    // MARK: - 备份

    private func startBackup() {
        guard !selectedIds.isEmpty else { return }

        let toBackup = apps.filter { selectedIds.contains($0.packageName) }
        isBackingUp = true
        progress = (0, toBackup.count)

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: Date())
        let model = ADBService.shared.getDeviceModel(device: device.id)
        let dirName = "\(model)_\(dateStr)"
        let backupDir = "\(NSHomeDirectory())/Downloads/\(dirName)"

        do {
            try FileManager.default.createDirectory(atPath: backupDir,
                                                    withIntermediateDirectories: true, attributes: nil)
        } catch {
            result = (0, toBackup.count, "")
            isBackingUp = false
            return
        }

        let shared = ADBService.shared
        var success = 0
        var failed = 0

        Task {
            for app in toBackup {
                currentApp = app.displayName
                let localPath = "\(backupDir)/\(app.packageName).apk"
                do {
                    _ = try shared.run(["-s", device.id, "pull", app.apkPath, localPath], timeout: 60)
                    success += 1
                } catch {
                    failed += 1
                }
                progress.current += 1
            }
            result = (success, failed, backupDir)
            isBackingUp = false
        }
    }
}
