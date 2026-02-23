import Foundation

struct RemoteLog {
    let id: Int64
    let deviceId: String
    let deviceName: String
    let appName: String
    let bundleId: String
    let windowTitle: String?
    let startTime: Date
    let endTime: Date
    let isIdle: Bool
    let tagName: String?
}
