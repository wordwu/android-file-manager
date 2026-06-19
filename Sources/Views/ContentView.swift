import SwiftUI

struct ContentView: View {
    // MARK: - 注入属性 (从 App 层传入)

    let deviceManager: DeviceManager
    let fileBrowser: FileBrowser
    let clipboardManager: ClipboardManager
    let searchManager: SearchManager
    let transferManager: TransferManager

    // MARK: - 本地状态

    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var showDeleteConfirm = false
    @State private var showRenameSheet = false
    @State private var renameText = ""
    @State private var renameMode: FileBrowser.RenameMode = .prefix
    @State private var appListVM = AppListViewModel()
    @State private var deviceInfoVM = DeviceInfoViewModel()
    @State private var showAppList = false
    @State private var showDeviceInfo = false
    @State private var showBackupSheet = false
    @State private var showAboutSheet = false
    @State private var viewMode: FileListView.ViewMode = .list
    @State private var thumbnailCache = ThumbnailCache()
    @State private var isRenaming = false

    // MARK: - Body

    var body: some View {
        mainView
            .toolbar(.hidden)
            .alert("确认删除", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    Task {
                        if let id = deviceManager.selectedDevice?.id {
                            let targetPath = fileBrowser.currentPath
                            await fileBrowser.deleteSelected(device: id)
                            await fileBrowser.loadDirectory(device: id, path: targetPath)
                        }
                    }
                }
            } message: {
                Text("确定要删除选中的 \(fileBrowser.selectionCount) 个项目吗？此操作不可撤销。")
            }
            .task {
                for window in NSApp.windows where window.identifier?.rawValue == "main" || window.isKeyWindow {
                    window.title = "安卓文件小助理"
                }
                deviceManager.onDisconnect = { [fileBrowser, searchManager] in
                    searchManager.clearSearch()
                    fileBrowser.clearSelection()
                    fileBrowser.files = []
                    appListVM.apps = []
                    deviceInfoVM.info = nil
                }
            }
            .onChange(of: deviceManager.selectedDevice) { _, newDevice in
                if newDevice == nil {
                    showAppList = false
                    showDeviceInfo = false
                    showRenameSheet = false
                }
            }
            .sheet(isPresented: $showRenameSheet) {
                renameSheetView
                    .interactiveDismissDisabled(isRenaming)
            }
            .sheet(isPresented: $showAppList) {
                if let device = deviceManager.selectedDevice {
                    AppListView(viewModel: appListVM, device: device)
                        .frame(minWidth: 600, idealWidth: 700, minHeight: 500, idealHeight: 600)
                }
            }
            .sheet(isPresented: $showDeviceInfo) {
                if let device = deviceManager.selectedDevice {
                    DeviceInfoView(viewModel: deviceInfoVM, device: device)
                        .frame(minWidth: 450, idealWidth: 500, minHeight: 400, idealHeight: 550)
                }
            }
            .sheet(isPresented: $showBackupSheet) {
                if let device = deviceManager.selectedDevice {
                    BackupAppView(device: device)
                }
            }
            .sheet(isPresented: $showAboutSheet) {
                AboutView()
            }
    }

    // MARK: - Main View

    private var mainView: some View {
        NavigationSplitView {
            DeviceListView(deviceManager: deviceManager, fileBrowser: fileBrowser)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            VStack(spacing: 0) {
                ToolbarView(
                    deviceManager: deviceManager,
                    fileBrowser: fileBrowser,
                    clipboardManager: clipboardManager,
                    searchManager: searchManager,
                    transferManager: transferManager,
                    searchText: $searchText,
                    searchTask: $searchTask,
                    showDeleteConfirm: $showDeleteConfirm,
                    showRenameSheet: $showRenameSheet,
                    renameText: $renameText,
                    showAppList: $showAppList,
                    showDeviceInfo: $showDeviceInfo,
                    showBackupSheet: $showBackupSheet,
                    showAboutSheet: $showAboutSheet,
                    viewMode: $viewMode
                )

                PathBarView(
                    fileBrowser: fileBrowser,
                    searchManager: searchManager,
                    viewMode: $viewMode
                )

                HStack(spacing: 0) {
                    FileListView(
                        deviceManager: deviceManager,
                        fileBrowser: fileBrowser,
                        searchManager: searchManager,
                        transferManager: transferManager,
                        viewMode: $viewMode,
                        searchText: searchText,
                        thumbnailCache: thumbnailCache
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // 右侧预览与详细信息面板
                    detailPanel
                        .frame(width: 260)
                        .frame(maxHeight: .infinity)
                }

                TransferPanelView(transferManager: transferManager)

                statusBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Status Bar

    /// 应用版本号（从 Info.plist 读取）
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "4.0.0"
    }

    /// 左侧状态文字：设备名 · 文件数
    private var statusLeft: String {
        guard let device = deviceManager.selectedDevice else {
            return "未连接设备"
        }
        let count = fileBrowser.files.count
        let selected = fileBrowser.selectionCount
        if selected > 0 {
            return "\(device.displayName) · 已选 \(selected)/\(count) 项"
        }
        return "\(device.displayName) · \(count) 个项目"
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(statusLeft)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let msg = fileBrowser.statusMessage {
                Circle()
                    .fill(.blue)
                    .frame(width: 4, height: 4)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("v\(appVersion)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospaced()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Rename Sheet

    private var renameSheetView: some View {
        VStack(spacing: 16) {
            Text("批量重命名")
                .font(.headline)

            Picker("模式", selection: $renameMode) {
                ForEach(FileBrowser.RenameMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            TextField("新名称", text: $renameText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("取消") {
                    showRenameSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("重命名") {
                    isRenaming = true
                    Task {
                        if let id = deviceManager.selectedDevice?.id {
                            await fileBrowser.renameSelected(
                                device: id, mode: renameMode, text: renameText
                            )
                            await fileBrowser.refresh(device: id)
                        }
                        isRenaming = false
                        showRenameSheet = false
                    }
                }
                .disabled(renameText.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding()
        .frame(width: 350)
    }

    // MARK: - 右侧预览与详细信息面板

    @ViewBuilder
    private var detailPanel: some View {
        if let file = fileBrowser.selectedFile, !file.isDirectory, fileBrowser.selectionCount == 1 {
            DetailPreviewView(file: file, fileBrowser: fileBrowser, deviceManager: deviceManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
        } else {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "info.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("选中文件即可预览")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
        }
    }
}
