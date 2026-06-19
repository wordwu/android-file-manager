import SwiftUI

struct FilePreviewView: View {
    @Bindable var deviceManager: DeviceManager
    @Bindable var fileBrowser: FileBrowser

    @State private var previewImage: NSImage?
    @State private var isLoadingPreview = false
    @State private var previewError: String?
    @State private var apkInfo: APKInfo?
    @State private var isLoadingAPK = false
    @State private var previewLoadTask: Task<Void, Never>? = nil
    @State private var apkLoadTask: Task<Void, Never>? = nil

    var body: some View {
        Group {
            if let file = fileBrowser.selectedFile, !file.isDirectory {
                VStack(spacing: 0) {
                    if isLoadingPreview {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = previewError {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let image = previewImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                    } else {
                        Image(systemName: file.iconName)
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("文件信息")
                            .font(.headline)
                        Group {
                            infoRow("名称", file.name)
                            infoRow("大小", file.sizeFormatted)
                            infoRow("路径", file.path)
                            infoRow("权限", file.permissions)
                            if let date = file.modifiedDate {
                                infoRow("修改", date.formatted())
                            }
                        }
                        .font(.caption)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // APK 信息
                    if file.name.hasSuffix(".apk") {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("APK 信息")
                                .font(.headline)
                            if isLoadingAPK {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("正在解析...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else if let info = apkInfo {
                                Group {
                                    if !info.appName.isEmpty {
                                        infoRow("应用名", info.appName)
                                    }
                                    if !info.packageName.isEmpty {
                                        infoRow("包名", info.packageName)
                                    }
                                    if !info.versionName.isEmpty {
                                        infoRow("版本", info.versionName)
                                    }
                                    if !info.versionCode.isEmpty {
                                        infoRow("版本号", info.versionCode)
                                    }
                                    let sdkStr = if !info.minSdk.isEmpty && !info.targetSdk.isEmpty {
                                        "min \(info.minSdk) / target \(info.targetSdk)"
                                    } else if !info.minSdk.isEmpty {
                                        "min \(info.minSdk)"
                                    } else if !info.targetSdk.isEmpty {
                                        "target \(info.targetSdk)"
                                    } else { "" }
                                    if !sdkStr.isEmpty {
                                        infoRow("SDK", sdkStr)
                                    }
                                    infoRow("大小", ByteCountFormatter().string(fromByteCount: info.size))
                                    if !info.permissions.isEmpty {
                                        Divider()
                                        Text("权限 (\(info.permissions.count))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        ScrollView {
                                            LazyVStack(alignment: .leading, spacing: 2) {
                                                ForEach(info.permissions.sorted(), id: \.self) { perm in
                                                    Text(perm)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        .frame(maxHeight: 150)
                                    }
                                }
                                .font(.caption)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                ContentUnavailableView("选择文件", systemImage: "doc.text.image",
                                       description: Text("点击文件查看预览和信息"))
            }
        }
        .task(id: fileBrowser.selectedFile) {
            loadPreview(fileBrowser.selectedFile)
        }
        .onDisappear {
            previewLoadTask?.cancel()
            apkLoadTask?.cancel()
        }
    }

    private func loadPreview(_ file: FileItem?) {
        previewLoadTask?.cancel()
        apkLoadTask?.cancel()
        previewImage = nil
        previewError = nil
        apkInfo = nil
        guard let file, let device = deviceManager.selectedDevice else { return }

        let ext = (file.name as NSString).pathExtension.lowercased()
        guard C.imageExts.contains(ext) || ext == "apk" else { return }

        let capturedPath = file.path
        if ext == "apk" {
            isLoadingAPK = true
            apkLoadTask = Task {
                defer { isLoadingAPK = false }
                do {
                    let info = try await ADBService.shared.getAPKInfo(device: device.id, remotePath: capturedPath)
                    if !Task.isCancelled { apkInfo = info }
                } catch {
                    // silently fail, apkInfo stays nil
                }
            }
            return
        }

        isLoadingPreview = true
        previewLoadTask = Task {
            defer { isLoadingPreview = false }
            do {
                let img = try await PreviewLoader.loadImage(from: capturedPath, deviceId: device.id, ext: ext)
                guard !Task.isCancelled else { return }
                previewImage = img
            } catch {
                if !Task.isCancelled { previewError = error.localizedDescription }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            Text(value)
                .lineLimit(3)
        }
    }
}
