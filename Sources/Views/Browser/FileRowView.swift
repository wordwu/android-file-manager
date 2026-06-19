import SwiftUI

struct FileRowView: View {
    let item: FileItem
    let isSelected: Bool
    let isMultiSelected: Bool
    let thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            // 多选指示
            if isMultiSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 14))
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 14))
            }

            // 图标 / 缩略图
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 22, height: 22)
                    .cornerRadius(3)
            } else {
                Image(systemName: item.iconName)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(item.isDirectory ? .blue : .secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(item.sizeFormatted)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let date = item.modifiedDate {
                        Text(date, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Text(item.permissions)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospaced()
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
}
