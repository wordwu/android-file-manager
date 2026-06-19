import SwiftUI

struct DeviceInfoView: View {
    @Bindable var viewModel: DeviceInfoViewModel
    let device: Device
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶栏
            HStack {
                Text("设备信息")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await viewModel.loadInfo(device: device.id) }
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
            
            Divider()
            
            // 内容
            if viewModel.isLoading {
                Spacer()
                ProgressView().scaleEffect(0.8)
                Text("正在读取设备信息...")
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
            } else if let info = viewModel.info {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        batterySection(info.battery)
                        Divider()
                        storageSection(info.storage)
                        Divider()
                        systemSection(info.system)
                    }
                    .padding(16)
                }
            }
        }
        .task {
            await viewModel.loadInfo(device: device.id)
        }
    }
    
    // MARK: - 电池
    @ViewBuilder
    private func batterySection(_ b: BatteryInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("🔋 电池")
                .font(.headline)
            
            HStack(spacing: 16) {
                // 电量环
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 6)
                        .frame(width: 56, height: 56)
                    Circle()
                        .trim(from: 0, to: CGFloat(b.level) / 100)
                        .stroke(batteryColor(b.level), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(-90))
                    Text("\(b.level)%")
                        .font(.system(size: 16, weight: .bold))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    infoRow("状态", b.status)
                    infoRow("健康", b.health)
                    infoRow("温度", b.tempText)
                    infoRow("技术", b.technology.isEmpty ? "未知" : b.technology)
                }
                .font(.caption)
            }
        }
    }
    
    private func batteryColor(_ level: Int) -> Color {
        if level >= 80 { return .green }
        if level >= 30 { return .yellow }
        return .red
    }
    
    // MARK: - 存储
    @ViewBuilder
    private func storageSection(_ s: StorageInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("💾 存储")
                .font(.headline)
            
            // 用量条
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(storageColor(s.usagePercent))
                            .frame(width: max(4, geo.size.width * CGFloat(s.usagePercent) / 100), height: 8)
                    }
                }
                .frame(height: 8)
                
                HStack {
                    Text("已用 \(s.usedText) / 共 \(s.totalText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(s.usagePercent))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("可用")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text(s.freeText)
                        .font(.caption).fontWeight(.medium)
                }
                VStack(alignment: .leading) {
                    Text("已用")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text(s.usedText)
                        .font(.caption).fontWeight(.medium)
                }
                VStack(alignment: .leading) {
                    Text("总计")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text(s.totalText)
                        .font(.caption).fontWeight(.medium)
                }
            }
        }
    }
    
    private func storageColor(_ pct: Double) -> Color {
        if pct >= 90 { return .red }
        if pct >= 70 { return .yellow }
        return .green
    }
    
    // MARK: - 系统
    @ViewBuilder
    private func systemSection(_ s: SystemInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("📱 系统")
                .font(.headline)
            
            infoRow("型号", s.modelText)
            infoRow("厂商", s.manufacturerText)
            infoRow("系统版本", s.versionText)
            infoRow("序列号", s.serialNo.isEmpty ? "未知" : s.serialNo)
            infoRow("Build", s.buildNumber.isEmpty ? "未知" : s.buildNumber)
        }
    }
    
    // MARK: - 通用信息行
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .lineLimit(1)
            Spacer()
        }
        .font(.caption)
    }
}
