import SwiftUI

struct CallLogView: View {
    @Bindable var viewModel: CallLogViewModel
    let device: Device
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Label("通话记录", systemImage: "phone.arrow.up.right")
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            Divider()
            
            if viewModel.isLoading {
                Spacer()
                ProgressView("加载中...")
                Spacer()
            } else if let error = viewModel.errorMessage {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundColor(.orange)
                    Text(error).font(.callout).foregroundColor(.secondary)
                }
                Spacer()
            } else if viewModel.logs.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "phone.arrow.up.right")
                        .font(.largeTitle).foregroundColor(.secondary)
                    Text("暂无通话记录").font(.callout).foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List(viewModel.logs) { item in
                    CallLogRow(item: item)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 480, height: 520)
        .task {
            await viewModel.load(device: device.id)
        }
    }
}

private struct CallLogRow: View {
    let item: CallLogItem
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.type.iconName)
                .font(.title3)
                .foregroundColor(item.type.color)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.phoneNumber)
                    .font(.body).fontWeight(.medium)
                Text(item.type.label)
                    .font(.caption).foregroundColor(item.type.color)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDuration(item.duration))
                    .font(.callout).foregroundColor(.secondary)
                Text(item.date, style: .date)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDuration(_ seconds: Int64) -> String {
        if seconds == 0 { return "" }
        let m = seconds / 60
        let s = seconds % 60
        return m > 0 ? "\(m)分\(s)秒" : "\(s)秒"
    }
}
