import Foundation

struct Device: Identifiable, Hashable {
    let id: String
    var model: String
    let state: DeviceState
    let connectionType: ConnectionType
    var displayName: String = ""

    enum DeviceState: String { case online, offline, unauthorized }
    enum ConnectionType: String { case usb, wireless }
}
