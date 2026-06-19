import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showCoffeeSheet = false

    var body: some View {
        VStack(spacing: 16) {
            // 图标
            if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
               let nsImage = NSImage(contentsOfFile: iconPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 80, height: 80)
            } else {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
            }

            Text("安卓文件小助理")
                .font(.title2)
                .fontWeight(.semibold)

            Text("版本 4.0.0")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("一个给 Android + Mac 用户的无痛文件管理器")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Divider()
                .frame(width: 200)

            // 特征列表
            VStack(alignment: .leading, spacing: 8) {
                AboutRow(icon: "cable.connector", text: "USB / 无线 ADB 双模连接")
                AboutRow(icon: "doc.on.doc", text: "复制、剪切、粘贴、拖拽上传")
                AboutRow(icon: "magnifyingglass", text: "递归搜索，打字自动触发")
                AboutRow(icon: "square.and.arrow.down", text: "APK 批量备份 + 安装")
                AboutRow(icon: "iphone.gen3.radiowaves.left.and.right", text: "屏幕镜像（scrcpy）")
                AboutRow(icon: "battery.75percent", text: "设备信息面板")
            }

            Divider()
                .frame(width: 200)

            Text("作者：AltairZheng（征）")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                showCoffeeSheet = true
            } label: {
                HStack {
                    Text("☕️ 请作者喝杯咖啡")
                        .font(.caption)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            Link("GitHub", destination: URL(string: "https://github.com/wordwu/android-file-manager")!)
                .font(.caption)

            Button("关闭") {
                dismiss()
            }
            .keyboardShortcut(.return, modifiers: [])
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 340)
        .sheet(isPresented: $showCoffeeSheet) {
            CoffeeView()
        }
    }
}

// MARK: - 咖啡赞赏码

private struct CoffeeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("☕️ 感谢支持")
                .font(.headline)

            HStack(alignment: .top, spacing: 24) {
                // 微信赞赏码
                VStack(spacing: 6) {
                    if let img = loadImage(named: "wechat_qr.jpg") {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 160, height: 160)
                    }
                    Text("微信赞赏")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // 支付宝收款码
                VStack(spacing: 6) {
                    if let img = loadImage(named: "alipay_qr.jpg") {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 160, height: 160)
                    }
                    Text("支付宝")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button("关闭") {
                dismiss()
            }
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(24)
        .frame(width: 400, height: 280)
    }

    private func loadImage(named name: String) -> NSImage? {
        guard let path = Bundle.main.path(forResource: name
            .replacingOccurrences(of: ".jpg", with: ""), ofType: "jpg") else { return nil }
        return NSImage(contentsOfFile: path)
    }
}

// MARK: - 功能行

private struct AboutRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.accentColor)
                .font(.caption)
            Text(text)
                .font(.caption)
        }
    }
}
