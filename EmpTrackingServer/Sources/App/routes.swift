import Vapor

func routes(_ app: Application) throws {
    app.get("health") { req in
        HTTPStatus.ok
    }

    try app.register(collection: DeviceController())
}
