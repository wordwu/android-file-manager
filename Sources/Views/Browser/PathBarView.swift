import SwiftUI

struct PathBarView: View {
    @Bindable var fileBrowser: FileBrowser
    @Bindable var searchManager: SearchManager
    @Binding var viewMode: FileListView.ViewMode

    @State private var showCopyAlert = false

    var body: some View {
        HStack(spacing: 4) {
            if searchManager.isSearching {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.blue)
                    Text("搜索: \(searchManager.searchQuery)")
                        .font(.caption).lineLimit(1)
                    if fileBrowser.isLoading {
                        ProgressView().scaleEffect(0.5)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            } else {
                // 复制路径按钮（前置）
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fileBrowser.currentPath, forType: .string)
                    showCopyAlert = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopyAlert = false
                    }
                } label: {
                    Image(systemName: showCopyAlert ? "checkmark" : "doc.on.doc").font(.caption)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("复制路径")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(pathComponents, id: \.path) { component in
                            if component.path != pathComponents.first?.path {
                                Image(systemName: "chevron.right")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            if component.path == fileBrowser.currentPath {
                                Text(component.name).font(.caption).fontWeight(.medium)
                            } else {
                                Button(component.name) {
                                    fileBrowser.navigateTo(path: component.path)
                                }
                                .buttonStyle(.plain).font(.caption)
                                .contentShape(Rectangle())
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    private var pathComponents: [(name: String, path: String)] {
        let parts = fileBrowser.currentPath.components(separatedBy: "/").filter { !$0.isEmpty }
        var result: [(String, String)] = []
        var accumulated = ""
        for part in parts {
            accumulated += "/\(part)"
            result.append((part, accumulated))
        }
        return result
    }
}
