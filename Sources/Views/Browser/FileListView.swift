import SwiftUI
import UniformTypeIdentifiers

struct FileListView: View {
    @Bindable var deviceManager: DeviceManager
    @Bindable var fileBrowser: FileBrowser
    @Bindable var searchManager: SearchManager
    @Bindable var transferManager: TransferManager
    @Binding var viewMode: ViewMode
    var searchText: String
    var thumbnailCache: ThumbnailCache

    // MARK: - Drag-to-select state
    @State private var dragStart: CGPoint? = nil
    @State private var dragRect: CGRect? = nil
    @State private var cellFrames: [String: CGRect] = [:]

    // MARK: - MTP hint
    @State private var showMTPHint = false

    enum ViewMode: String, CaseIterable {
        case list = "列表"
        case grid = "图标"
    }

    // 已加载文件总大小（MB）
    private var totalLoadedSize: String {
        let bytes = fileBrowser.files.reduce(0) { $0 + $1.size }
        if bytes < 1024 * 1024 {
            let kb = Double(bytes) / 1024.0
            return String(format: "%.1f KB", kb)
        }
        let mb = Double(bytes) / (1024.0 * 1024.0)
        if mb < 1024 {
            return String(format: "%.1f MB", mb)
        }
        return String(format: "%.2f GB", mb / 1024.0)
    }

    var body: some View {
        Group {
            if let device = deviceManager.selectedDevice, device.state == .online {
                VStack(spacing: 0) {
                    if fileBrowser.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if searchManager.isSearching && fileBrowser.files.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else if fileBrowser.files.isEmpty {
                        if isRestrictedPath {
                            ContentUnavailableView(
                                "目录受限",
                                systemImage: "lock.shield",
                                description: Text("Android 11+ 的 Scoped Storage 限制\n应用无法通过 ADB 直接访问此目录\n\n路径: \(fileBrowser.currentPath)")
                            )
                        } else {
                            ContentUnavailableView("空目录", systemImage: "folder",
                                                   description: Text(fileBrowser.currentPath))
                        }
                    } else if viewMode == .list {
                        fileList
                    } else {
                        iconGrid
                    }
                }
                .task(id: "\(deviceManager.selectedDevice?.id ?? "none")/\(fileBrowser.currentPath)") {
                    if let id = deviceManager.selectedDevice?.id {
                        await fileBrowser.loadDirectory(device: id)
                    }
                }
                .onChange(of: fileBrowser.currentPath) { _, _ in
                    thumbnailCache.clear()
                }
            } else {
                VStack(spacing: 0) {
                    ContentUnavailableView(
                        deviceManager.selectedDevice == nil ? "选择设备" : "设备未连接",
                        systemImage: deviceManager.selectedDevice == nil
                            ? "iphone.gen3" : "iphone.gen3.slash",
                        description: Text(deviceManager.selectedDevice == nil
                            ? "在侧边栏选择一个已连接的安卓设备"
                            : "设备已断开，请重新连接")
                    )
                    if showMTPHint && deviceManager.devices.isEmpty {
                        MTPHintView()
                    }
                }
            }
        }
        .task {
            // 延迟 10 秒后显示 MTP 提示
            try? await Task.sleep(for: .seconds(10))
            showMTPHint = true
        }
    }

    // MARK: - 点击手势（列表/图标复用）
    
    private struct FileTapModifier: ViewModifier {
        let item: FileItem
        let browser: FileBrowser
        
        func body(content: Content) -> some View {
            content
                .onTapGesture(count: 2) {
                    browser.clearSelection()
                    if item.isDirectory { browser.navigateInto(item) }
                }
                .onTapGesture(count: 1) {
                    if NSEvent.modifierFlags.contains(.command) {
                        browser.toggleSelection(item)
                    } else {
                        browser.selectedFile = item
                        browser.selectedFiles.removeAll()
                    }
                }
        }
    }
    
    // MARK: - 列表视图

    private var fileList: some View {
        List {
            ForEach(fileBrowser.sortedFiles) { item in
                FileRowView(
                    item: item,
                    isSelected: isItemActive(item),
                    isMultiSelected: fileBrowser.selectedFiles.contains(item),
                    thumbnail: thumbnailCache.get(item.path)
                )
                .contentShape(Rectangle())
                .modifier(FileTapModifier(item: item, browser: fileBrowser))
                .onAppear {
                    if let device = deviceManager.selectedDevice {
                        thumbnailCache.load(for: item, device: device)
                    }
                }
                .contextMenu { contextMenu(items: [item]) }
            }
            if !fileBrowser.files.isEmpty {
                HStack {
                    Spacer()
                    Text("已加载 \(totalLoadedSize) · \(fileBrowser.files.count) 项")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            if fileBrowser.hasMore {
                HStack {
                    Spacer()
                    Button {
                        if let device = deviceManager.selectedDevice {
                            Task { await fileBrowser.loadMore(device: device.id) }
                        }
                    } label: {
                        if fileBrowser.isLoading {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Label("加载更多…", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(fileBrowser.isLoading)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .onDrop(of: [.fileURL], isTargeted: .none) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - 图标网格

    private func gridCell(_ item: FileItem) -> some View {
        let active = isItemActive(item)
        let multi = fileBrowser.selectedFiles.contains(item)

        return VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                if let thumb = thumbnailCache.get(item.path) {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .cornerRadius(4)
                } else {
                    Image(systemName: item.iconName)
                        .font(.system(size: 32))
                        .foregroundStyle(item.isDirectory ? .blue : .secondary)
                        .frame(height: 40)
                }

                // 多选标记
                if multi {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                        .background(Circle().fill(.white).frame(width: 12, height: 12))
                        .offset(x: -6, y: -6)
                }
            }

            Text(item.name)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if !item.isDirectory {
                Text(item.sizeFormatted)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(active ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .modifier(FileTapModifier(item: item, browser: fileBrowser))
    }

    private var iconGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 90, maximum: 120), spacing: 8)]

        return GeometryReader { outerGeo in
            ZStack {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(fileBrowser.sortedFiles) { item in
                            gridCell(item)
                                .background(
                                    GeometryReader { cellGeo in
                                        Color.clear.preference(
                                            key: CellFramePreferenceKey.self,
                                            value: [item.id: cellGeo.frame(in: .named("iconGrid"))]
                                        )
                                    }
                                )
                                .onAppear {
                                    if let device = deviceManager.selectedDevice {
                                        thumbnailCache.load(for: item, device: device)
                                    }
                                }
                                .contextMenu { contextMenu(items: [item]) }
                        }
                    }
                    .padding(12)
                    
                    // 已加载大小
                    if !fileBrowser.files.isEmpty {
                        HStack {
                            Spacer()
                            Text("已加载 \(totalLoadedSize) · \(fileBrowser.files.count) 项")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .padding(.bottom, 4)
                    }
                    // 加载更多按钮
                    if fileBrowser.hasMore {
                        HStack {
                            Spacer()
                            Button {
                                if let device = deviceManager.selectedDevice {
                                    Task { await fileBrowser.loadMore(device: device.id) }
                                }
                            } label: {
                                if fileBrowser.isLoading {
                                    ProgressView().scaleEffect(0.6)
                                } else {
                                    Label("加载更多…", systemImage: "arrow.down.circle")
                                }
                            }
                            .disabled(fileBrowser.isLoading)
                            Spacer()
                        }
                        .padding(.bottom, 12)
                    }
                }
                .coordinateSpace(name: "iconGrid")

                // 拖拽选择矩形
                if let rect = dragRect {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.2))
                        .border(Color.accentColor, width: 1)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
        }
        .onPreferenceChange(CellFramePreferenceKey.self) { frames in
            cellFrames.merge(frames) { _, new in new }
        }
        .gesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .named("iconGrid"))
                .onChanged { value in
                    let start = value.startLocation
                    let current = value.location
                    let rect = CGRect(
                        x: min(start.x, current.x),
                        y: min(start.y, current.y),
                        width: abs(current.x - start.x),
                        height: abs(current.y - start.y)
                    )
                    dragStart = start
                    dragRect = rect

                    // 选中与拖拽矩形重叠的单元格
                    let overlapping = fileBrowser.sortedFiles.filter { item in
                        guard let frame = cellFrames[item.id] else { return false }
                        return rect.intersects(frame)
                    }
                    fileBrowser.selectedFiles = Set(overlapping)
                    if overlapping.count == 1 {
                        fileBrowser.selectedFile = overlapping.first
                    } else {
                        fileBrowser.selectedFile = nil
                    }
                }
                .onEnded { _ in
                    dragStart = nil
                    dragRect = nil
                }
        )
        .onDrop(of: [.fileURL], isTargeted: .none) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - 辅助

    /// 检测是否为 Android 11+ 受限路径（Scoped Storage）
    private var isRestrictedPath: Bool {
        let path = fileBrowser.currentPath.lowercased()
        return C.restrictedPathPatterns.contains(where: { path.contains($0) })
    }

    private func isItemActive(_ item: FileItem) -> Bool {
        fileBrowser.selectedFile == item || fileBrowser.selectedFiles.contains(item)
    }

    // MARK: - 右键菜单

    @ViewBuilder
    private func contextMenu(items: Set<FileItem>) -> some View {
        if let item = items.first, let device = deviceManager.selectedDevice {
            Button {
                downloadFile(item, from: device)
            } label: {
                Label("下载到 Mac", systemImage: "arrow.down")
            }

            Divider()

            // APK 安装入口
            if item.name.hasSuffix(".apk") {
                Button {
                    installAPKFromPhone(item, device: device)
                } label: {
                    Label("安装到手机", systemImage: "square.and.arrow.down.on.square")
                }
                Divider()
            }

            Button(role: .destructive) {
                Task {
                    do {
                        try await Task {
                            try ADBService.shared.deleteItem(device: device.id, path: item.path)
                        }.value
                        await fileBrowser.refresh(device: device.id)
                    } catch {
                        await MainActor.run {
                            fileBrowser.setStatus("删除失败：\(error.localizedDescription)")
                        }
                    }
                }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }

        if deviceManager.selectedDevice != nil {
            Button {
                createNewFolder()
            } label: {
                Label("新建文件夹", systemImage: "folder.badge.plus")
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let device = deviceManager.selectedDevice else { return false }
        let destPath = fileBrowser.currentPath
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                let remotePath = "\(destPath)/\(url.lastPathComponent)"
                let fileSize = (try? FileManager.default
                    .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                let task = TransferTask(deviceId: device.id, direction: .push,
                                        localPath: url.path, remotePath: remotePath,
                                        fileName: url.lastPathComponent, totalBytes: fileSize)
                Task { @MainActor in transferManager.enqueue(task: task) }
            }
        }
        return true
    }

    private func downloadFile(_ item: FileItem, from device: Device) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.name
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let task = TransferTask(deviceId: device.id, direction: .pull,
                                    localPath: url.path, remotePath: item.path,
                                    fileName: item.name, totalBytes: item.size)
            transferManager.enqueue(task: task)
        }
    }

    private func createNewFolder() {
        guard let device = deviceManager.selectedDevice else { return }
        let base = fileBrowser.currentPath.hasSuffix("/")
            ? "\(fileBrowser.currentPath)新建文件夹" : "\(fileBrowser.currentPath)/新建文件夹"
        var newPath = base
        var counter = 1
        while fileBrowser.files.contains(where: { $0.path == newPath }) {
            newPath = "\(base) \(counter)"
            counter += 1
        }
        let path = newPath
        Task {
            do {
                try await Task {
                    try ADBService.shared.createDirectory(device: device.id, path: path)
                }.value
                await fileBrowser.refresh(device: device.id)
            } catch {
                await MainActor.run {
                    fileBrowser.setStatus("创建文件夹失败：\(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - APK 安装
    
    private func installAPKFromPhone(_ item: FileItem, device: Device) {
        Task {
            await ADBService.installAPKWithStatus(
                device: device.id, remotePath: item.path, fileName: item.name
            ) { msg in
                fileBrowser.setStatus(msg)
            }
        }
    }
}

// MARK: - Cell Frame Preference Key (drag-to-select)

private struct CellFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - MTP Hint View

private struct MTPHintView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("未检测到 ADB 设备？试试：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("1. 手机开启 USB 调试模式")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("2. 或通过 MTP 模式连接（需安装 Android File Transfer）")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
