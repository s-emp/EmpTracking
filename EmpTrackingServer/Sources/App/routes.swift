import Vapor

func routes(_ app: Application) throws {
    app.get("health") { req in
        HTTPStatus.ok
    }
}
