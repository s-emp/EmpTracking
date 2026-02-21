@testable import App
import VaporTesting
import Testing

@Suite("Sync Pull Tests")
struct SyncPullTests {
    @Test("Pull returns logs from other devices")
    func pullReturnsLogsFromOtherDevices() async throws {
        try await withApp(configure: configure) { app in
            // Register two devices
            for (id, name) in [("dev-1", "Mac 1"), ("dev-2", "Mac 2")] {
                try await app.testing().test(.POST, "api/v1/devices", beforeRequest: { req in
                    try req.content.encode(RegisterDeviceRequest(device_id: id, name: name))
                }, afterResponse: { res async in
                    #expect(res.status == .created)
                })
            }

            // Push log from dev-2
            let pushBody = SyncPushRequest(
                device_id: "dev-2",
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
            })

            // Pull as dev-1 - should see dev-2's logs
            try await app.testing().test(.GET, "api/v1/sync/pull?device_id=dev-1&since=0",
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    let body = try res.content.decode(SyncPullResponse.self)
                    #expect(body.logs.count == 1)
                    #expect(body.logs[0].device_id == "dev-2")
                    #expect(body.logs[0].device_name == "Mac 2")
                    #expect(body.logs[0].bundle_id == "com.apple.Safari")
                    #expect(body.logs[0].app_name == "Safari")
                    #expect(body.logs[0].tag_name == "Browsing")
                })

            // Pull as dev-2 - should NOT see own logs
            try await app.testing().test(.GET, "api/v1/sync/pull?device_id=dev-2&since=0",
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    let body = try res.content.decode(SyncPullResponse.self)
                    #expect(body.logs.count == 0)
                })
        }
    }

    @Test("Pull respects timestamp filter")
    func pullRespectsTimestamp() async throws {
        try await withApp(configure: configure) { app in
            // Register two devices
            for (id, name) in [("dev-1", "Mac 1"), ("dev-2", "Mac 2")] {
                try await app.testing().test(.POST, "api/v1/devices", beforeRequest: { req in
                    try req.content.encode(RegisterDeviceRequest(device_id: id, name: name))
                }, afterResponse: { res async in
                    #expect(res.status == .created)
                })
            }

            // Push two logs from dev-2 at different times
            let pushBody = SyncPushRequest(
                device_id: "dev-2",
                apps: [AppPayload(bundle_id: "com.apple.Safari", app_name: "Safari")],
                tags: [],
                logs: [
                    LogPayload(
                        client_log_id: 1,
                        bundle_id: "com.apple.Safari",
                        window_title: "Early",
                        start_time: 1000.0,
                        end_time: 1060.0,
                        is_idle: 0,
                        tag_name: nil
                    ),
                    LogPayload(
                        client_log_id: 2,
                        bundle_id: "com.apple.Safari",
                        window_title: "Late",
                        start_time: 2000.0,
                        end_time: 2060.0,
                        is_idle: 0,
                        tag_name: nil
                    )
                ]
            )

            try await app.testing().test(.POST, "api/v1/sync/push", beforeRequest: { req in
                try req.content.encode(pushBody)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let body = try res.content.decode(SyncPushResponse.self)
                #expect(body.synced_count == 2)
            })

            // Pull with since=1500 - should only get the late log
            try await app.testing().test(.GET, "api/v1/sync/pull?device_id=dev-1&since=1500",
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    let body = try res.content.decode(SyncPullResponse.self)
                    #expect(body.logs.count == 1)
                    #expect(body.logs[0].window_title == "Late")
                })

            // Pull with since=0 - should get both logs
            try await app.testing().test(.GET, "api/v1/sync/pull?device_id=dev-1&since=0",
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    let body = try res.content.decode(SyncPullResponse.self)
                    #expect(body.logs.count == 2)
                })
        }
    }
}
