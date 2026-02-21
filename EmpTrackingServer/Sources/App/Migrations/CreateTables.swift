import Fluent

struct CreateTables: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("devices")
            .field("id", .string, .identifier(auto: false))
            .field("name", .string, .required)
            .field("last_sync", .double)
            .create()

        try await database.schema("apps")
            .field("id", .int, .identifier(auto: true))
            .field("bundle_id", .string, .required)
            .field("app_name", .string, .required)
            .unique(on: "bundle_id")
            .create()

        try await database.schema("tags")
            .field("id", .int, .identifier(auto: true))
            .field("name", .string, .required)
            .field("color_light", .string, .required)
            .field("color_dark", .string, .required)
            .unique(on: "name")
            .create()

        try await database.schema("activity_logs")
            .field("id", .int, .identifier(auto: true))
            .field("device_id", .string, .required)
            .field("app_id", .int, .required)
            .field("window_title", .string)
            .field("start_time", .double, .required)
            .field("end_time", .double, .required)
            .field("is_idle", .int, .required)
            .field("tag_id", .int)
            .field("client_log_id", .int64, .required)
            .foreignKey("device_id", references: "devices", "id")
            .foreignKey("app_id", references: "apps", "id")
            .foreignKey("tag_id", references: "tags", "id")
            .unique(on: "device_id", "client_log_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("activity_logs").delete()
        try await database.schema("tags").delete()
        try await database.schema("apps").delete()
        try await database.schema("devices").delete()
    }
}
