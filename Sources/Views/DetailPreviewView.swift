import SwiftUI

/// 右侧预览与详细信息面板
struct DetailPreviewView: View {
    let file: FileItem
    let fileBrowser: FileBrowser
    let deviceManager: DeviceManager

    @State private var previewImage: NSImage?

    private var isImage: Bool {
        let ext = (file.name as NSString).pathExtension.lowercased()
        return C.imageExts.contains(ext)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // 缩略图 / 图标预览
                previewSection

                Divider()

                // 详细信息
                infoSection
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadPreview() }
        .onChange(of: file.path) { _, _ in
            previewImage = nil
            loadPreview()
        }
    }

    // MARK: - 预览区域

    private var previewSection: some View {
        VStack(alignment: .center, spacing: 8) {
            thumbnailView
                .frame(maxWidth: .infinity, minHeight: 140)

            Text(file.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let img = previewImage {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 220)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: file.iconName)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 详细信息

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("文件信息")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            infoRow("类型", fileTypeLabel)
            infoRow("大小", file.isDirectory ? "--" : file.sizeFormatted)
            infoRow("权限", file.permissions.isEmpty ? "-" : file.permissions)
            infoRow("修改时间", formatDate(file.modifiedDate))

            if !file.isDirectory {
                infoRow("路径", file.path)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value.isEmpty ? "-" : value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    private var fileTypeLabel: String {
        if file.isDirectory { return "文件夹" }
        let ext = (file.name as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "文件" : "\(ext) 文件"
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "-" }
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df.string(from: date)
    }

    // MARK: - 缩略图加载

    private func loadPreview() {
        guard isImage, let device = deviceManager.selectedDevice else { return }
        let ext = (file.name as NSString).pathExtension
        Task {
            if let img = try? await PreviewLoader.loadImage(from: file.path, deviceId: device.id, ext: ext) {
                await MainActor.run { previewImage = img }
            }
        }
    }
}
