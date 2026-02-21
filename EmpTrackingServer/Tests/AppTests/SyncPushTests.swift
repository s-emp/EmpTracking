@testable import App
import VaporTesting
import Testing

@Suite("Sync Push Tests")
struct SyncPushTests {
    @Test("Push creates apps, tags, and logs")
    func pushCreatesAppsTagsAndLogs() async throws {
        try await withApp(configure: configure) { app in
            // Register device first
            try await app.testing().test(.POST, "api/v1/devices", beforeRequest: { req in
                try req.content.encode(RegisterDeviceRequest(
                    device_id: "dev-1",
                    name: "Test Mac"
                ))
            }, afterResponse: { res async in
                #expect(res.status == .created)
            })

            let pushBody = SyncPushRequest(
                device_id: "dev-1",
                apps: [AppPayload(bundle_id: "com.apple.Safari", app_name: "Safari")],
                tags: [TagPayload(name: "Browsing", color_light: "#0000FF", color_dark: "#0000AA")],
                logs: [LogPayload(
                    client_log_id: 1,
                    bundle_id: "com.apple.Safari",
                    window_title: "Apple",
                    start_time: 1000.0,
                    end_time: 1060.0,
                    is_idle: 0,
                    tag_name: "Browsing"
                )]
            )

            try await app.testing().test(.POST, "api/v1/sync/push", beforeRequest: { req in
                try req.content.encode(pushBody)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let body = try res.content.decode(SyncPushResponse.self)
                #expect(body.synced_count == 1)
            })
        }
    }

    @Test("Push ignores duplicate logs")
    func pushIgnoresDuplicateLogs() async throws {
        try await withApp(configure: configure) { app in
            // Register device first
            try await app.testing().test(.POST, "api/v1/devices", beforeRequest: { req in
                try req.content.encode(RegisterDeviceRequest(
                    device_id: "dev-1",
                    name: "Test Mac"
                ))
            }, afterResponse: { res async in
                #expect(res.status == .created)
            })

            let pushBody = SyncPushRequest(
                device_id: "dev-1",
                apps: [AppPayload(bundle_id: "com.apple.Safari", app_name: "Safari")],
                tags: [],
                logs: [LogPayload(
                    client_log_id: 1,
                    bundle_id: "com.apple.Safari",
                    window_title: "Apple",
                    start_time: 1000.0,
                    end_time: 1060.0,
                    is_idle: 0,
                    tag_name: nil
                )]
            )

            // First push
            try await app.testing().test(.POST, "api/v1/sync/push", beforeRequest: { req in
                try req.content.encode(pushBody)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let body = try res.content.decode(SyncPushResponse.self)
                #expect(body.synced_count == 1)
            })

            // Second push with same log - should be ignored
            try await app.testing().test(.POST, "api/v1/sync/push", beforeRequest: { req in
                try req.content.encode(pushBody)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let body = try res.content.decode(SyncPushResponse.self)
                #expect(body.synced_count == 0)
            })
        }
    }
}
