import Vapor

@main
enum Entrypoint {
    static func main() async throws {
        let env = try Environment.detect()
        let app = try await Application.make(env)
        try await configure(app)
        try await app.execute()
        try await app.asyncShutdown()
    }
}
