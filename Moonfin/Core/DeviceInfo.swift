import Foundation

struct DeviceInfo {
    let clientName: String
    let clientVersion: String
    let deviceName: String
    let deviceId: String

    init(
        clientName: String = AppConstants.clientName,
        clientVersion: String = AppConstants.clientVersion,
        deviceName: String = AppConstants.deviceName,
        deviceId: String = AppConstants.deviceId
    ) {
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.deviceName = deviceName
        self.deviceId = deviceId
    }
}
