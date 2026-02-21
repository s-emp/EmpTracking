import Vapor
import Fluent
import FluentSQLiteDriver

func configure(_ app: Application) async throws {
    let dbPath = app.directory.workingDirectory + "emptracking-server.sqlite"
    app.databases.use(.sqlite(.file(dbPath)), as: .sqlite)

    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = 8080

    app.migrations.add(CreateTables())
    try await app.autoMigrate()

    try routes(app)
}
