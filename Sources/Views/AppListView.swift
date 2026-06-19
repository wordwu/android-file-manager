import SwiftUI

struct AppListView: View {
    @Bindable var viewModel: AppListViewModel
    let device: Device
    @Environment(\.dismiss) private var dismiss
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏：关闭 + 刷新
            HStack {
                Text("已安装应用")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.apps = []
                    Task { await viewModel.loadApps(device: device.id) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(viewModel.isLoading)
                .padding(.trailing, 4)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // 搜索 + 过滤
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("搜索应用...", text: $viewModel.filterText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                Toggle("系统应用", isOn: $viewModel.showSystemApps)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            // 统计
            HStack {
                Text("共 \(viewModel.filteredApps.count) 个应用")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !viewModel.showSystemApps {
                    Text("已隐藏 \(viewModel.systemCount) 个系统应用")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            // 列表
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Text("正在读取应用列表...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else if let error = viewModel.error {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else if viewModel.filteredApps.isEmpty {
                Spacer()
                Text("没有匹配的应用")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(viewModel.filteredApps) { app in
                    AppRowView(app: app, deviceId: device.id, onUninstall: {
                        Task {
                            await viewModel.uninstall(app, device: device.id)
                        }
                    }, onExport: {
                        Task {
                            await viewModel.exportAPK(app, device: device.id)
                        }
                    })
                }
                .listStyle(.inset)
            }
        }
        .task {
            await viewModel.loadApps(device: device.id)
        }
        .onChange(of: viewModel.statusMessage) { _, _ in
            guard let msg = viewModel.statusMessage else { return }
            dismissTask?.cancel()
            dismissTask = Task {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { return }
                if viewModel.statusMessage == msg { viewModel.statusMessage = nil }
            }
        }
        .overlay(alignment: .bottom) {
            if let msg = viewModel.statusMessage {
                HStack {
                    Image(systemName: "info.circle.fill").font(.caption)
                    Text(msg).font(.caption)
                    Spacer()
                    Button { viewModel.statusMessage = nil } label: {
                        Image(systemName: "xmark").font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.blue.opacity(0.1))
            }
        }
    }
}

private struct AppRowView: View {
    let app: AppInfo
    let deviceId: String
    let onUninstall: () -> Void
    let onExport: () -> Void
    @State private var showConfirm = false

    var body: some View {
        HStack(spacing: 8) {
            // 图标：真图标 > 字母头像
            if let iconPath = app.iconPath, let nsImage = NSImage(contentsOfFile: iconPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)
            } else {
                Text(app.displayName.prefix(1).uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(letterColor(for: app.packageName))
                    .cornerRadius(6)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.body)
                    .lineLimit(1)
                Text(app.packageName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(app.isSystem ? "系统" : "三方")
                .font(.caption2)
                .foregroundColor(app.isSystem ? .secondary : .accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(app.isSystem ? Color.secondary.opacity(0.1) : Color.accentColor.opacity(0.1))
                .cornerRadius(4)

            if !app.isSystem {
                Button {
                    onExport()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("导出 APK")
                
                Button {
                    showConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .alert("确认卸载", isPresented: $showConfirm) {
                    Button("取消", role: .cancel) {}
                    Button("卸载", role: .destructive) { onUninstall() }
                } message: {
                    Text("确定要卸载「\(app.displayName)」吗？")
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    /// 根据包名生成稳定的颜色
    private func letterColor(for pkg: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint, .cyan, .red]
        var hash = 0
        for c in pkg.utf8 { hash = hash &+ Int(c) &* 31 }
        return colors[abs(hash) % colors.count]
    }
}