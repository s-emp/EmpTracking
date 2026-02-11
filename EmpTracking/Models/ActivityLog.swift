import Foundation

struct ActivityLog {
    let id: Int64
    let appId: Int64
    let windowTitle: String?
    let startTime: Date
    var endTime: Date
    let isIdle: Bool
}
