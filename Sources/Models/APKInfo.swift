import Foundation

struct APKInfo {
    let packageName: String
    let versionName: String
    let versionCode: String
    let minSdk: String
    let targetSdk: String
    let appName: String
    let permissions: [String]
    let size: Int64
    
    init(fromBadging output: String, fileSize: Int64 = 0) {
        var pkg = "", verName = "", verCode = "", minSdk = "", targetSdk = "", label = ""
        var perms: [String] = []
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let pattern = #"(\S+)='([^']*)'"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let keyRange = Range(match.range(at: 1), in: line),
                  let valueRange = Range(match.range(at: 2), in: line) else { continue }
            let key = String(line[keyRange])
            let value = String(line[valueRange])
            
            switch true {
            case key.hasPrefix("package:"): 
                let parts = key.components(separatedBy: " ")
                pkg = parts.count > 1 ? String(parts[1].dropFirst(5)) : value
                for part in parts {
                    if part.hasPrefix("versionName=") { 
                        verName = String(part.dropFirst(13)).replacingOccurrences(of: "'", with: "")
                    }
                    if part.hasPrefix("versionCode=") { 
                        verCode = String(part.dropFirst(13)).replacingOccurrences(of: "'", with: "")
                    }
                }
            case key.hasPrefix("sdkVersion:"): minSdk = value
            case key.hasPrefix("targetSdkVersion:"): targetSdk = value
            case key.hasPrefix("application-label"):
                // 优先中文标签，已设置则 zh-CN 覆盖
                if label.isEmpty || key.hasSuffix("-zh-CN") || key.hasSuffix("-zh") {
                    label = value
                }
            case key == "label": label = value
            case key.hasPrefix("uses-permission:"): perms.append(value)
            default: break
            }
        }
        packageName = pkg
        versionName = verName
        versionCode = verCode
        self.minSdk = minSdk
        self.targetSdk = targetSdk
        appName = label
        permissions = perms
        size = fileSize
    }
}
