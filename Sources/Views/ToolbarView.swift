import SwiftUI

struct ToolbarView: View {
    // MARK: - 服务

    var deviceManager: DeviceManager
    @Bindable var fileBrowser: FileBrowser
    @Bindable var clipboardManager: ClipboardManager
    @Bindable var searchManager: SearchManager
    var transferManager: TransferManager

    // MARK: - 绑定

    @Binding var searchText: String
    @Binding var searchTask: Task<Void, Never>?
    @Binding var showDeleteConfirm: Bool
    @Binding var showRenameSheet: Bool
    @Binding var renameText: String
    @Binding var showAppList: Bool
    @Binding var showDeviceInfo: Bool
    @Binding var showBackupSheet: Bool
    @Binding var showAboutSheet: Bool
    @Binding var viewMode: FileListView.ViewMode

    // MARK: - Body

    var body: some View {
        toolbarRow
        toolbarRow2
    }

    // MARK: - 工具栏 第一行：操作按钮

    private var toolbarRow: some View {
        HStack(spacing: 4) {
            // 侧边栏切换
            tbBtn("sidebar.leading", nil) {
                NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
            }

            tbBtn("arrow.left", "后退", disabled: fileBrowser.pathStack.isEmpty) {
                fileBrowser.navigateBack()
            }

            tbBtn("arrow.turn.left.up", "向上", disabled: fileBrowser.currentPath == "/") {
                fileBrowser.navigateUp()
            }

            Divider().frame(height: 18)

            tbBtn("house", "主页") {
                Task {
                    if let id = deviceManager.selectedDevice?.id {
                        await fileBrowser.goHome(device: id)
                    }
                }
            }

            tbBtn("arrow.clockwise", "刷新", disabled: deviceManager.selectedDevice == nil) {
                Task {
                    if let id = deviceManager.selectedDevice?.id {
                        await fileBrowser.refresh(device: id)
                    }
                }
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider().frame(height: 18)

            tbBtn("doc.on.doc", "复制", disabled: fileBrowser.selectionCount == 0) {
                clipboardManager.copySelected(paths: fileBrowser.allSelectedPaths())
            }

            tbBtn("scissors", "剪切", disabled: fileBrowser.selectionCount == 0) {
                clipboardManager.cutSelected(paths: fileBrowser.allSelectedPaths())
            }

            tbBtn("doc.on.clipboard", "粘贴", disabled: clipboardManager.clipboard.isEmpty) {
                Task {
                    if let id = deviceManager.selectedDevice?.id {
                        await clipboardManager.paste(to: fileBrowser.currentPath, device: id)
                        await fileBrowser.refresh(device: id)
                    }
                }
            }

            tbBtn("trash", "删除", disabled: fileBrowser.selectionCount == 0, danger: true) {
                showDeleteConfirm = true
            }
            .keyboardShortcut(.delete, modifiers: .command)

            tbBtn("arrow.down.to.line", "下载", disabled: fileBrowser.selectionCount == 0) {
                downloadSelected()
            }

            // APK 安装按钮
            if let file = fileBrowser.selectedFile, file.name.hasSuffix(".apk"), fileBrowser.selectedFiles.isEmpty {
                tbBtn("square.and.arrow.down.on.square", "安装") {
                    installSelectedAPK(file)
                }
            }

            // 屏幕镜像按钮
            tbBtn("iphone.gen3.radiowaves.left.and.right", "屏幕镜像", disabled: deviceManager.selectedDevice == nil) {
                if let id = deviceManager.selectedDevice?.id {
                    ADBService.shared.launchScrcpy(deviceId: id)
                }
            }

            // 备份应用按钮
            tbBtn("tray.and.arrow.down", "备份应用", disabled: deviceManager.selectedDevice == nil) {
                showBackupSheet = true
            }

            // 关于按钮
            tbBtn("info.circle", "关于", disabled: false) {
                showAboutSheet = true
            }

            Spacer()
        }
        .padding(.bottom, 5)
    }

    // MARK: - 工具栏 第二行：搜索 / 视图 / 排序 / 类型 / 重命名

    private var toolbarRow2: some View {
        HStack(spacing: 4) {
            // 搜索框
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("搜索文件...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .frame(width: 160)
            .onChange(of: searchText) { _, query in
                guard let device = deviceManager.selectedDevice else { return }
                searchTask?.cancel()
                if query.isEmpty {
                    searchManager.clearSearch()
                    Task { await fileBrowser.refresh(device: device.id) }
                } else {
                    let captured = query
                    searchTask = Task {
                        try? await Task.sleep(for: .seconds(0.3))
                        if Task.isCancelled { return }
                        await searchManager.search(device: device.id, query: captured, currentPath: fileBrowser.currentPath)
                    }
                }
            }

            tbBtn("rectangle.3.group", "应用", disabled: deviceManager.selectedDevice == nil) {
                showAppList.toggle()
            }

            tbBtn("iphone.gen3", "设备信息", disabled: deviceManager.selectedDevice == nil) {
                showDeviceInfo.toggle()
            }

            // 视图切换（自定义分段）
            HStack(spacing: 0) {
                ForEach(FileListView.ViewMode.allCases, id: \.self) { mode in
                    Button(action: { viewMode = mode }) {
                        Text(mode.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .frame(minWidth: 36)
                            .background(viewMode == mode ? Color.accentColor : Color.clear)
                            .foregroundStyle(viewMode == mode ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(.quaternary.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary, lineWidth: 0.5))

            Picker("排序", selection: $fileBrowser.sortOrder) {
                ForEach(FileBrowser.SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).font(.caption).tag(order)
                }
            }
            .pickerStyle(.menu)
            .font(.caption)
            .frame(width: 100)

            Picker("类型", selection: $fileBrowser.fileTypeFilter) {
                ForEach(FileBrowser.FileTypeFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).font(.caption).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .font(.caption)
            .frame(width: 100)

            tbBtn("pencil", "重命名", disabled: fileBrowser.selectionCount == 0) {
                showRenameSheet = true
                renameText = fileBrowser.selectedFile?.name ?? ""
            }

            Spacer()
        }
        .padding(.leading, 8)
        .padding(.bottom, 5)
    }

    // MARK: - 按钮构建器

    private func tbBtn(_ icon: String, _ label: String?, disabled: Bool = false,
                        danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: icon).font(.caption)
                if let label { Text(label).font(.caption) }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .foregroundStyle(danger ? .red : disabled ? Color.secondary : .primary)
        .disabled(disabled)
    }

    // MARK: - 下载

    private func downloadSelected() {
        guard let device = deviceManager.selectedDevice else { return }
        let paths = fileBrowser.allSelectedPaths()
        let downloadsDir = NSHomeDirectory() + "/Downloads"
        for path in paths {
            let name = (path as NSString).lastPathComponent
            let dest = downloadsDir + "/" + name
            let task = TransferTask(deviceId: device.id, direction: .pull,
                                    localPath: dest, remotePath: path,
                                    fileName: name, totalBytes: 0)
            transferManager.enqueue(task: task)
        }
    }

    // MARK: - APK 安装

    private func installSelectedAPK(_ file: FileItem) {
        guard let device = deviceManager.selectedDevice else { return }
        Task {
            await ADBService.installAPKWithStatus(
                device: device.id, remotePath: file.path, fileName: file.name
            ) { msg in
                fileBrowser.setStatus(msg)
            }
        }
    }
}
