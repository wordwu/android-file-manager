import SwiftUI

struct TransferPanelView: View {
    @Bindable var transferManager: TransferManager

    var body: some View {
        if !transferManager.tasks.isEmpty {
            VStack(spacing: 0) {
                Divider()
                ScrollView(.vertical) {
                    VStack(spacing: 6) {
                        ForEach(transferManager.tasks) { task in
                            transferRow(task)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: C.transferPanelHeight)
            }
            .background(.regularMaterial)
        }
    }

    private func transferRow(_ task: TransferTask) -> some View {
        HStack(spacing: 8) {
            Image(systemName: task.direction == .push ? "arrow.up" : "arrow.down")
                .font(.caption)
                .foregroundStyle(.blue)

            Text(task.fileName)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            switch task.status {
            case .queued:
                Text("排队中").font(.caption2).foregroundStyle(.secondary)
            case .transferring:
                ProgressView(value: task.progress)
                    .frame(width: 80)
                Text("\(Int(task.progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .frame(width: 32, alignment: .trailing)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }
}
