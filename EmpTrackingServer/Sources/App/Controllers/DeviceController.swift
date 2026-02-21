import Vapor
import Fluent

struct DeviceController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api", "v1")
        api.post("devices", use: register)
    }

    @Sendable
    func register(req: Request) async throws -> Response {
        let input = try req.content.decode(RegisterDeviceRequest.self)

        if let existing = try await Device.find(input.device_id, on: req.db) {
            existing.name = input.name
            try await existing.save(on: req.db)
            return Response(status: .ok)
        }

        let device = Device(id: input.device_id, name: input.name)
        try await device.save(on: req.db)
        return Response(status: .created)
    }
}
