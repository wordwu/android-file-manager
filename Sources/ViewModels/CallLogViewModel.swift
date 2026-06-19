import Foundation
import Observation

@MainActor
@Observable
final class CallLogViewModel {
    var logs: [CallLogItem] = []
    var isLoading = false
    var errorMessage: String?
    
    private let adb = ADBService.shared
    
    func load(device: String) async {
        isLoading = true
        errorMessage = nil
        logs = []
        do {
            logs = try await Task { [adb] in
                try adb.getCallLogs(device: device)
            }.value
            if logs.isEmpty {
                errorMessage = "未获取到通话记录（设备可能不支持或权限不足）"
            }
            androidFMLog("callLog: \(logs.count) entries")
        } catch {
            errorMessage = "获取失败: \(error.localizedDescription)"
            androidFMLog("callLog: error \(error.localizedDescription)")
        }
        isLoading = false
    }
}
