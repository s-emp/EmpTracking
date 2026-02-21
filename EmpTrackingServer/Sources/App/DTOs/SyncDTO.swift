import Vapor

struct SyncPushRequest: Content {
    let device_id: String
    let apps: [AppPayload]
    let tags: [TagPayload]
    let logs: [LogPayload]
}

struct AppPayload: Content {
    let bundle_id: String
    let app_name: String
}

struct TagPayload: Content {
    let name: String
    let color_light: String
    let color_dark: String
}

struct LogPayload: Content {
    let client_log_id: Int64
    let bundle_id: String
    let window_title: String?
    let start_time: Double
    let end_time: Double
    let is_idle: Int
    let tag_name: String?
}

struct SyncPushResponse: Content {
    let synced_count: Int
}

struct SyncPullResponse: Content {
    let logs: [RemoteLogPayload]
    let server_time: Double
}

struct RemoteLogPayload: Content {
    let device_id: String
    let device_name: String
    let bundle_id: String
    let app_name: String
    let window_title: String?
    let start_time: Double
    let end_time: Double
    let is_idle: Int
    let tag_name: String?
}
