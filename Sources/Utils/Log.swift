import Foundation

func androidFMLog(_ msg: String) {
    // 日志脱敏：去除设备序列号和 IP 地址
    let sanitized = msg
        .replacingOccurrences(of: #"adb -s \S+"#, with: "adb -s [device]", options: .regularExpression)
        .replacingOccurrences(of: #"device=\S+"#, with: "device=[device]", options: .regularExpression)
        .replacingOccurrences(of: #"\b(\d{1,3}\.){3}\d{1,3}\b"#, with: "[ip]", options: .regularExpression)
    let line = "[\(Date().formatted(.iso8601))] \(sanitized)\n"
    guard let data = line.data(using: .utf8) else { return }
    let logDir = "\(NSHomeDirectory())/Library/Logs"
    try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
    let path = "\(logDir)/androidfm.log"
    if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
    } else {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
