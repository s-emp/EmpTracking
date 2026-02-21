@testable import App
import VaporTesting
import Testing

@Suite("Device Tests")
struct DeviceTests {
    @Test("Register device creates new device")
    func registerDevice() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.POST, "api/v1/devices", beforeRequest: { req in
                try req.content.encode(RegisterDeviceRequest(
                    device_id: "test-uuid",
                    name: "Test Mac"
                ))
            }, afterResponse: { res async in
                #expect(res.status == .ok || res.status == .created)
            })
        }
    }

    @Test("Register device twice is idempotent")
    func registerDeviceTwiceIsIdempotent() async throws {
        try await withApp(configure: configure) { app in
            let body = RegisterDeviceRequest(device_id: "test-uuid", name: "Test Mac")

            try await app.testing().test(.POST, "api/v1/devices", beforeRequest: { req in
                try req.content.encode(body)
            }, afterResponse: { res async in
                #expect(res.status == .created)
            })

            try await app.testing().test(.POST, "api/v1/devices", beforeRequest: { req in
                try req.content.encode(body)
            }, afterResponse: { res async in
                #expect(res.status == .ok)
            })
        }
    }
}
