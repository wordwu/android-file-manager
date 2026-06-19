import Foundation

struct FileItem: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let permissions: String
    let modifiedDate: Date?

    var sizeFormatted: String {
        guard !isDirectory else { return "--" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var iconName: String {
        if isDirectory { return "folder" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo"
        case "mp4", "mkv", "avi", "mov": return "film"
        case "mp3", "wav", "flac", "aac": return "music.note"
        case "apk": return "shippingbox"
        case "pdf": return "doc.richtext"
        case "zip", "rar", "7z": return "doc.zipper"
        default: return "doc"
        }
    }
}
