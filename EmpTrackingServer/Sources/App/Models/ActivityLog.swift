import Fluent
import Vapor

final class ServerActivityLog: Model, Content, @unchecked Sendable {
    static let schema = "activity_logs"

    @ID(custom: "id", generatedBy: .database)
    var id: Int?

    @Field(key: "device_id")
    var deviceId: String

    @Field(key: "app_id")
    var appId: Int

    @OptionalField(key: "window_title")
    var windowTitle: String?

    @Field(key: "start_time")
    var startTime: Double

    @Field(key: "end_time")
    var endTime: Double

    @Field(key: "is_idle")
    var isIdle: Int

    @OptionalField(key: "tag_id")
    var tagId: Int?

    @Field(key: "client_log_id")
    var clientLogId: Int64

    init() {}
}
