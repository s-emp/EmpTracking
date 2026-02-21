import Fluent
import Vapor

final class TrackedTag: Model, Content, @unchecked Sendable {
    static let schema = "tags"

    @ID(custom: "id", generatedBy: .database)
    var id: Int?

    @Field(key: "name")
    var name: String

    @Field(key: "color_light")
    var colorLight: String

    @Field(key: "color_dark")
    var colorDark: String

    init() {}

    init(name: String, colorLight: String, colorDark: String) {
        self.name = name
        self.colorLight = colorLight
        self.colorDark = colorDark
    }
}
