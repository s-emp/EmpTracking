import Fluent
import Vapor

final class TrackedApp: Model, Content, @unchecked Sendable {
    static let schema = "apps"

    @ID(custom: "id", generatedBy: .database)
    var id: Int?

    @Field(key: "bundle_id")
    var bundleId: String

    @Field(key: "app_name")
    var appName: String

    init() {}

    init(bundleId: String, appName: String) {
        self.bundleId = bundleId
        self.appName = appName
    }
}
