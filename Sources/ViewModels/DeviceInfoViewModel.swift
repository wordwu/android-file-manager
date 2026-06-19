import Foundation
import Observation

@MainActor
@Observable
final class DeviceInfoViewModel {
    var info: DeviceInfo?
    var isLoading = false
    var error: String?
    
    private let adb = ADBService.shared
    
    func loadInfo(device: String) async {
        isLoading = true
        error = nil
        do {
            info = try await Task { [adb] in
                try adb.getFullDeviceInfo(device: device)
            }.value
            androidFMLog("deviceInfo: loaded")
        } catch {
            self.error = "设备信息获取失败：\(error.localizedDescription)"
            androidFMLog("deviceInfo: error \(error.localizedDescription)")
        }
        isLoading = false
    }
}
