import SwiftUI

struct DeviceListView: View {
    @Bindable var deviceManager: DeviceManager
    @Bindable var fileBrowser: FileBrowser

    @State private var ipAddress = ""
    @State private var port = "\(C.adbPort)"
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("设备") {
                    if deviceManager.devices.isEmpty {
                        Text("未检测到设备")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                    ForEach(deviceManager.devices) { device in
                        deviceRow(device)
                    }
                }

                if let device = deviceManager.selectedDevice, !fileBrowser.bookmarks.isEmpty {
                    Section("书签") {
                        ForEach(fileBrowser.bookmarks) { bm in
                            bookmarkRow(bookmark: bm, device: device)
                        }
                    }
                }

                Section("无线连接") {
                    HStack {
                        TextField("IP 地址", text: $ipAddress)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                        Text(":")
                        TextField("端口", text: $port)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                    }
                    Button {
                        Task { await deviceManager.connectWireless(ip: ipAddress,
                                                                   port: Int(port) ?? C.adbPort) }
                    } label: {
                        Label("连接", systemImage: "link")
                    }
                    .disabled(ipAddress.isEmpty)
                }
            }
            .listStyle(.sidebar)
        }
        .onAppear { deviceManager.startPolling() }
        .onDisappear { deviceManager.stopPolling() }
        .alert("错误", isPresented: $showError) {
            Button("确定") { deviceManager.errorMessage = nil }
        } message: {
            Text(deviceManager.errorMessage ?? "")
        }
        .onChange(of: deviceManager.errorMessage) { _, newValue in
            showError = newValue != nil
        }
    }

    private func deviceRow(_ device: Device) -> some View {
        let isSelected = deviceManager.selectedDevice?.id == device.id
        return HStack {
            Image(systemName: device.connectionType == .usb
                  ? "cable.connector" : "wifi")
                .foregroundStyle(device.state == .online ? .green : .red)
            VStack(alignment: .leading) {
                Text(friendlyName(for: device))
                    .font(.body)
                Text(device.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if device.connectionType == .wireless {
                Button {
                    Task { await deviceManager.disconnect(device: device) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else if device.connectionType == .usb && device.state == .online {
                Button {
                    Task { await deviceManager.enableWireless(for: device) }
                } label: {
                    Image(systemName: "wifi")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(4)
        .onTapGesture {
            deviceManager.selectedDevice = device
        }
    }

    private func bookmarkRow(bookmark: FileBrowser.Bookmark, device: Device) -> some View {
        HStack {
            Image(systemName: "bookmark")
                .foregroundStyle(.orange)
                .font(.caption)
            Text(bookmark.name)
                .font(.callout)
            Spacer()
            Text(bookmark.path)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await fileBrowser.loadDirectory(device: device.id, path: bookmark.path) }
        }
        .contextMenu {
            Button("移除书签") {
                fileBrowser.removeBookmark(bookmark)
            }
        }
    }

    private func friendlyName(for device: Device) -> String {
        // 1. 手机自己报的市场名（最准，如 "Xiaomi 15"、"OPPO Find N5"）
        if !device.displayName.isEmpty { return device.displayName }
        // 2. 本地型号库精确匹配
        if let name = C.deviceModelNames[device.model] { return name }
        let model = device.model
        // 模糊匹配: 显示厂商前缀
        if model.hasPrefix("SM-") { return "三星 \(model)" }
        if model.hasPrefix("CPH") || model.hasPrefix("PG") { return "OPPO \(model)" }
        if model.hasPrefix("PHY") || model.hasPrefix("PHT") || model.hasPrefix("PHW") ||
           model.hasPrefix("PHB") || model.hasPrefix("PJA") || model.hasPrefix("PJC") ||
           model.hasPrefix("PJB") || model.hasPrefix("PJG") { return "OPPO \(model)" }
        if model.hasPrefix("LE") || model.hasPrefix("PHK") { return "一加 \(model)" }
        if model.hasPrefix("V") && model.count >= 5 { return "vivo \(model)" }
        if model.hasPrefix("ALN") || model.hasPrefix("MNA") || model.hasPrefix("ADA") ||
           model.hasPrefix("LIO") || model.hasPrefix("NOH") { return "华为 \(model)" }
        if model.hasPrefix("MAA") || model.hasPrefix("BVL") || model.hasPrefix("LGE") ||
           model.hasPrefix("MAG") { return "荣耀 \(model)" }
        return model
    }
}
