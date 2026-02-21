import Fluent
import Vapor

final class Device: Model, Content, @unchecked Sendable {
    static let schema = "devices"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Field(key: "name")
    var name: String

    @OptionalField(key: "last_sync")
    var lastSync: Double?

    init() {}

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
