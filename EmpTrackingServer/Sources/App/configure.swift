import Vapor
import Fluent
import FluentSQLiteDriver

func configure(_ app: Application) async throws {
    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else {
        let dbPath = app.directory.workingDirectory + "emptracking-server.sqlite"
        app.databases.use(.sqlite(.file(dbPath)), as: .sqlite)
    }

    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = 8080

    // Allow large sync payloads (up to 10MB)
    app.routes.defaultMaxBodySize = "10mb"

    app.migrations.add(CreateTables())
    try await app.autoMigrate()

    try routes(app)
}
