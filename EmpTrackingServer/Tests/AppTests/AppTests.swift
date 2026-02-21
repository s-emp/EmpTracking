@testable import App
import XCTVapor
import Testing

@Suite("App Tests")
struct AppTests {
    @Test("Health endpoint returns OK")
    func healthEndpoint() async throws {
        let app = try await Application.make(.testing)
        try await configure(app)
        defer { Task { try? await app.asyncShutdown() } }

        try await app.test(.GET, "health") { res async in
            #expect(res.status == .ok)
        }
    }
}
