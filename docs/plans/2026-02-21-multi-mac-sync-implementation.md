# Multi-Mac Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable EmpTracking to sync activity data between multiple Macs via a local Vapor server on Mac Mini.

**Architecture:** Offline-first clients push/pull to a central Vapor HTTP server on the LAN. Each client keeps a local SQLite DB and syncs every 60 seconds. Server is the single source of truth.

**Tech Stack:** Swift, Vapor 4 + Fluent + SQLite driver (server), raw SQLite3 (client), AppKit.

**Design doc:** `docs/plans/2026-02-21-multi-mac-sync-design.md`

---

## Phase 1: Vapor Server

### Task 1: Scaffold Vapor project

**Files:**
- Create: `EmpTrackingServer/Package.swift`
- Create: `EmpTrackingServer/Sources/App/entrypoint.swift`
- Create: `EmpTrackingServer/Sources/App/configure.swift`
- Create: `EmpTrackingServer/Sources/App/routes.swift`

**Step 1: Create directory and Package.swift**

```bash
mkdir -p EmpTrackingServer/Sources/App
mkdir -p EmpTrackingServer/Tests/AppTests
```

`EmpTrackingServer/Package.swift`:
```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EmpTrackingServer",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
            ]
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "XCTVapor", package: "vapor"),
            ]
        ),
    ]
)
```

**Step 2: Create entrypoint**

`EmpTrackingServer/Sources/App/entrypoint.swift`:
```swift
import Vapor

@main
enum Entrypoint {
    static func main() async throws {
        let env = try Environment.detect()
        let app = try await Application.make(env)
        try configure(app)
        try await app.execute()
        try await app.asyncShutdown()
    }
}
```

**Step 3: Create configure.swift**

`EmpTrackingServer/Sources/App/configure.swift`:
```swift
import Vapor
import Fluent
import FluentSQLiteDriver

func configure(_ app: Application) throws {
    let dbPath = app.directory.workingDirectory + "emptracking-server.sqlite"
    app.databases.use(.sqlite(.file(dbPath)), as: .sqlite)

    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = 8080

    try routes(app)
}
```

**Step 4: Create routes.swift**

`EmpTrackingServer/Sources/App/routes.swift`:
```swift
import Vapor

func routes(_ app: Application) throws {
    app.get("health") { req in
        HTTPStatus.ok
    }
}
```

**Step 5: Build and verify**

Run: `cd EmpTrackingServer && swift build`
Expected: Build succeeds

**Step 6: Commit**

```bash
git add EmpTrackingServer/
git commit -m "feat: scaffold Vapor server project with health endpoint"
```

---

### Task 2: Server Fluent models and migrations

**Files:**
- Create: `EmpTrackingServer/Sources/App/Models/Device.swift`
- Create: `EmpTrackingServer/Sources/App/Models/App.swift`
- Create: `EmpTrackingServer/Sources/App/Models/Tag.swift`
- Create: `EmpTrackingServer/Sources/App/Models/ActivityLog.swift`
- Create: `EmpTrackingServer/Sources/App/Migrations/CreateTables.swift`
- Modify: `EmpTrackingServer/Sources/App/configure.swift`

**Step 1: Write Device model**

`EmpTrackingServer/Sources/App/Models/Device.swift`:
```swift
import Fluent
import Vapor

final class Device: Model, Content, @unchecked Sendable {
    static let schema = "devices"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Field(key: "name")
    var name: String

    @OptionalField(key: "last_sync")
    var lastSync: Double?

    init() {}

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
```

**Step 2: Write App model**

`EmpTrackingServer/Sources/App/Models/App.swift`:
```swift
import Fluent
import Vapor

final class TrackedApp: Model, Content, @unchecked Sendable {
    static let schema = "apps"

    @ID(custom: "id", generatedBy: .database)
    var id: Int?

    @Field(key: "bundle_id")
    var bundleId: String

    @Field(key: "app_name")
    var appName: String

    init() {}

    init(bundleId: String, appName: String) {
        self.bundleId = bundleId
        self.appName = appName
    }
}
```

**Step 3: Write Tag model**

`EmpTrackingServer/Sources/App/Models/Tag.swift`:
```swift
import Fluent
import Vapor

final class TrackedTag: Model, Content, @unchecked Sendable {
    static let schema = "tags"

    @ID(custom: "id", generatedBy: .database)
    var id: Int?

    @Field(key: "name")
    var name: String

    @Field(key: "color_light")
    var colorLight: String

    @Field(key: "color_dark")
    var colorDark: String

    init() {}

    init(name: String, colorLight: String, colorDark: String) {
        self.name = name
        self.colorLight = colorLight
        self.colorDark = colorDark
    }
}
```

**Step 4: Write ActivityLog model**

`EmpTrackingServer/Sources/App/Models/ActivityLog.swift`:
```swift
import Fluent
import Vapor

final class ServerActivityLog: Model, Content, @unchecked Sendable {
    static let schema = "activity_logs"

    @ID(custom: "id", generatedBy: .database)
    var id: Int?

    @Field(key: "device_id")
    var deviceId: String

    @Field(key: "app_id")
    var appId: Int

    @OptionalField(key: "window_title")
    var windowTitle: String?

    @Field(key: "start_time")
    var startTime: Double

    @Field(key: "end_time")
    var endTime: Double

    @Field(key: "is_idle")
    var isIdle: Int

    @OptionalField(key: "tag_id")
    var tagId: Int?

    @Field(key: "client_log_id")
    var clientLogId: Int64

    init() {}
}
```

**Step 5: Write migration**

`EmpTrackingServer/Sources/App/Migrations/CreateTables.swift`:
```swift
import Fluent

struct CreateTables: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("devices")
            .field("id", .string, .identifier(auto: false))
            .field("name", .string, .required)
            .field("last_sync", .double)
            .create()

        try await database.schema("apps")
            .field("id", .int, .identifier(auto: true))
            .field("bundle_id", .string, .required)
            .field("app_name", .string, .required)
            .unique(on: "bundle_id")
            .create()

        try await database.schema("tags")
            .field("id", .int, .identifier(auto: true))
            .field("name", .string, .required)
            .field("color_light", .string, .required)
            .field("color_dark", .string, .required)
            .unique(on: "name")
            .create()

        try await database.schema("activity_logs")
            .field("id", .int, .identifier(auto: true))
            .field("device_id", .string, .required)
            .field("app_id", .int, .required)
            .field("window_title", .string)
            .field("start_time", .double, .required)
            .field("end_time", .double, .required)
            .field("is_idle", .int, .required)
            .field("tag_id", .int)
            .field("client_log_id", .int64, .required)
            .foreignKey("device_id", references: "devices", "id")
            .foreignKey("app_id", references: "apps", "id")
            .foreignKey("tag_id", references: "tags", "id")
            .unique(on: "device_id", "client_log_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("activity_logs").delete()
        try await database.schema("tags").delete()
        try await database.schema("apps").delete()
        try await database.schema("devices").delete()
    }
}
```

**Step 6: Register migration in configure.swift**

Add to `configure.swift` before `try routes(app)`:
```swift
app.migrations.add(CreateTables())
try await app.autoMigrate()
```

**Step 7: Build and verify**

Run: `cd EmpTrackingServer && swift build`
Expected: Build succeeds

**Step 8: Commit**

```bash
git add EmpTrackingServer/Sources/App/Models/ EmpTrackingServer/Sources/App/Migrations/
git add EmpTrackingServer/Sources/App/configure.swift
git commit -m "feat: add server Fluent models and migrations"
```

---

### Task 3: POST /devices endpoint

**Files:**
- Create: `EmpTrackingServer/Sources/App/Controllers/DeviceController.swift`
- Create: `EmpTrackingServer/Sources/App/DTOs/DeviceDTO.swift`
- Modify: `EmpTrackingServer/Sources/App/routes.swift`
- Test: `EmpTrackingServer/Tests/AppTests/DeviceTests.swift`

**Step 1: Write the failing test**

`EmpTrackingServer/Tests/AppTests/DeviceTests.swift`:
```swift
@testable import App
import XCTVapor
import Testing

struct DeviceTests {
    @Test func registerDevice() async throws {
        let app = try await Application.make(.testing)
        try configure(app)
        defer { Task { try await app.asyncShutdown() } }

        try await app.test(.POST, "api/v1/devices", beforeRequest: { req in
            try req.content.encode(RegisterDeviceRequest(
                device_id: "test-uuid",
                name: "Test Mac"
            ))
        }, afterResponse: { res async in
            #expect(res.status == .ok || res.status == .created)
        })
    }

    @Test func registerDeviceTwiceIsIdempotent() async throws {
        let app = try await Application.make(.testing)
        try configure(app)
        defer { Task { try await app.asyncShutdown() } }

        let body = RegisterDeviceRequest(device_id: "test-uuid", name: "Test Mac")

        try await app.test(.POST, "api/v1/devices", beforeRequest: { req in
            try req.content.encode(body)
        }, afterResponse: { res async in
            #expect(res.status == .created)
        })

        try await app.test(.POST, "api/v1/devices", beforeRequest: { req in
            try req.content.encode(body)
        }, afterResponse: { res async in
            #expect(res.status == .ok)
        })
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd EmpTrackingServer && swift test --filter DeviceTests`
Expected: Compilation error (RegisterDeviceRequest not found)

**Step 3: Write DTO**

`EmpTrackingServer/Sources/App/DTOs/DeviceDTO.swift`:
```swift
import Vapor

struct RegisterDeviceRequest: Content {
    let device_id: String
    let name: String
}
```

**Step 4: Write controller**

`EmpTrackingServer/Sources/App/Controllers/DeviceController.swift`:
```swift
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
```

**Step 5: Register controller in routes.swift**

```swift
import Vapor

func routes(_ app: Application) throws {
    app.get("health") { req in
        HTTPStatus.ok
    }

    try app.register(collection: DeviceController())
}
```

**Step 6: Run tests**

Run: `cd EmpTrackingServer && swift test --filter DeviceTests`
Expected: PASS

**Step 7: Commit**

```bash
git add EmpTrackingServer/
git commit -m "feat: add POST /devices endpoint with registration"
```

---

### Task 4: POST /sync/push endpoint

**Files:**
- Create: `EmpTrackingServer/Sources/App/DTOs/SyncDTO.swift`
- Create: `EmpTrackingServer/Sources/App/Controllers/SyncController.swift`
- Modify: `EmpTrackingServer/Sources/App/routes.swift`
- Test: `EmpTrackingServer/Tests/AppTests/SyncPushTests.swift`

**Step 1: Write DTOs**

`EmpTrackingServer/Sources/App/DTOs/SyncDTO.swift`:
```swift
import Vapor

struct SyncPushRequest: Content {
    let device_id: String
    let apps: [AppPayload]
    let tags: [TagPayload]
    let logs: [LogPayload]
}

struct AppPayload: Content {
    let bundle_id: String
    let app_name: String
}

struct TagPayload: Content {
    let name: String
    let color_light: String
    let color_dark: String
}

struct LogPayload: Content {
    let client_log_id: Int64
    let bundle_id: String
    let window_title: String?
    let start_time: Double
    let end_time: Double
    let is_idle: Int
    let tag_name: String?
}

struct SyncPushResponse: Content {
    let synced_count: Int
}

struct SyncPullResponse: Content {
    let logs: [RemoteLogPayload]
    let server_time: Double
}

struct RemoteLogPayload: Content {
    let device_id: String
    let device_name: String
    let bundle_id: String
    let app_name: String
    let window_title: String?
    let start_time: Double
    let end_time: Double
    let is_idle: Int
    let tag_name: String?
}
```

**Step 2: Write the failing test**

`EmpTrackingServer/Tests/AppTests/SyncPushTests.swift`:
```swift
@testable import App
import XCTVapor
import Testing

struct SyncPushTests {
    @Test func pushCreatesAppsTagsAndLogs() async throws {
        let app = try await Application.make(.testing)
        try configure(app)
        defer { Task { try await app.asyncShutdown() } }

        // Register device first
        try await app.test(.POST, "api/v1/devices", beforeRequest: { req in
            try req.content.encode(RegisterDeviceRequest(device_id: "dev-1", name: "MacBook"))
        })

        let push = SyncPushRequest(
            device_id: "dev-1",
            apps: [AppPayload(bundle_id: "com.apple.Safari", app_name: "Safari")],
            tags: [TagPayload(name: "Work", color_light: "#4CAF50", color_dark: "#81C784")],
            logs: [LogPayload(
                client_log_id: 1,
                bundle_id: "com.apple.Safari",
                window_title: "GitHub",
                start_time: 1708500000.0,
                end_time: 1708501800.0,
                is_idle: 0,
                tag_name: "Work"
            )]
        )

        try await app.test(.POST, "api/v1/sync/push", beforeRequest: { req in
            try req.content.encode(push)
        }, afterResponse: { res async in
            #expect(res.status == .ok)
            let body = try? res.content.decode(SyncPushResponse.self)
            #expect(body?.synced_count == 1)
        })
    }

    @Test func pushIgnoresDuplicateLogs() async throws {
        let app = try await Application.make(.testing)
        try configure(app)
        defer { Task { try await app.asyncShutdown() } }

        try await app.test(.POST, "api/v1/devices", beforeRequest: { req in
            try req.content.encode(RegisterDeviceRequest(device_id: "dev-1", name: "MacBook"))
        })

        let push = SyncPushRequest(
            device_id: "dev-1",
            apps: [AppPayload(bundle_id: "com.apple.Safari", app_name: "Safari")],
            tags: [],
            logs: [LogPayload(
                client_log_id: 1,
                bundle_id: "com.apple.Safari",
                window_title: "GitHub",
                start_time: 1708500000.0,
                end_time: 1708501800.0,
                is_idle: 0,
                tag_name: nil
            )]
        )

        // Push twice
        for _ in 0..<2 {
            try await app.test(.POST, "api/v1/sync/push", beforeRequest: { req in
                try req.content.encode(push)
            }, afterResponse: { res async in
                #expect(res.status == .ok)
            })
        }
    }
}
```

**Step 3: Run test to verify it fails**

Run: `cd EmpTrackingServer && swift test --filter SyncPushTests`
Expected: FAIL (SyncController not registered)

**Step 4: Write SyncController push**

`EmpTrackingServer/Sources/App/Controllers/SyncController.swift`:
```swift
import Vapor
import Fluent

struct SyncController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api", "v1", "sync")
        api.post("push", use: push)
        api.get("pull", use: pull)
    }

    @Sendable
    func push(req: Request) async throws -> SyncPushResponse {
        let input = try req.content.decode(SyncPushRequest.self)

        // Upsert apps
        for appPayload in input.apps {
            let existing = try await TrackedApp.query(on: req.db)
                .filter(\.$bundleId == appPayload.bundle_id)
                .first()
            if existing == nil {
                let app = TrackedApp(bundleId: appPayload.bundle_id, appName: appPayload.app_name)
                try await app.save(on: req.db)
            }
        }

        // Upsert tags
        for tagPayload in input.tags {
            let existing = try await TrackedTag.query(on: req.db)
                .filter(\.$name == tagPayload.name)
                .first()
            if existing == nil {
                let tag = TrackedTag(
                    name: tagPayload.name,
                    colorLight: tagPayload.color_light,
                    colorDark: tagPayload.color_dark
                )
                try await tag.save(on: req.db)
            }
        }

        // Insert logs (skip duplicates)
        var syncedCount = 0
        for logPayload in input.logs {
            let duplicate = try await ServerActivityLog.query(on: req.db)
                .filter(\.$deviceId == input.device_id)
                .filter(\.$clientLogId == logPayload.client_log_id)
                .first()
            if duplicate != nil { continue }

            guard let app = try await TrackedApp.query(on: req.db)
                .filter(\.$bundleId == logPayload.bundle_id)
                .first(),
                let appId = app.id else { continue }

            var tagId: Int? = nil
            if let tagName = logPayload.tag_name {
                tagId = try await TrackedTag.query(on: req.db)
                    .filter(\.$name == tagName)
                    .first()?.id
            }

            let log = ServerActivityLog()
            log.deviceId = input.device_id
            log.appId = appId
            log.windowTitle = logPayload.window_title
            log.startTime = logPayload.start_time
            log.endTime = logPayload.end_time
            log.isIdle = logPayload.is_idle
            log.tagId = tagId
            log.clientLogId = logPayload.client_log_id
            try await log.save(on: req.db)
            syncedCount += 1
        }

        // Update device last_sync
        if let device = try await Device.find(input.device_id, on: req.db) {
            device.lastSync = Date().timeIntervalSince1970
            try await device.save(on: req.db)
        }

        return SyncPushResponse(synced_count: syncedCount)
    }

    @Sendable
    func pull(req: Request) async throws -> SyncPullResponse {
        // Placeholder — implemented in Task 5
        return SyncPullResponse(logs: [], server_time: Date().timeIntervalSince1970)
    }
}
```

**Step 5: Register in routes.swift**

Add to `routes.swift`:
```swift
try app.register(collection: SyncController())
```

**Step 6: Run tests**

Run: `cd EmpTrackingServer && swift test --filter SyncPushTests`
Expected: PASS

**Step 7: Commit**

```bash
git add EmpTrackingServer/
git commit -m "feat: add POST /sync/push endpoint"
```

---

### Task 5: GET /sync/pull endpoint

**Files:**
- Modify: `EmpTrackingServer/Sources/App/Controllers/SyncController.swift`
- Test: `EmpTrackingServer/Tests/AppTests/SyncPullTests.swift`

**Step 1: Write the failing test**

`EmpTrackingServer/Tests/AppTests/SyncPullTests.swift`:
```swift
@testable import App
import XCTVapor
import Testing

struct SyncPullTests {
    @Test func pullReturnsLogsFromOtherDevices() async throws {
        let app = try await Application.make(.testing)
        try configure(app)
        defer { Task { try await app.asyncShutdown() } }

        // Register two devices
        for (id, name) in [("dev-1", "MacBook"), ("dev-2", "Mac Mini")] {
            try await app.test(.POST, "api/v1/devices", beforeRequest: { req in
                try req.content.encode(RegisterDeviceRequest(device_id: id, name: name))
            })
        }

        // Push from dev-2
        let push = SyncPushRequest(
            device_id: "dev-2",
            apps: [AppPayload(bundle_id: "com.apple.Safari", app_name: "Safari")],
            tags: [],
            logs: [LogPayload(
                client_log_id: 1,
                bundle_id: "com.apple.Safari",
                window_title: "GitHub",
                start_time: 1708500000.0,
                end_time: 1708501800.0,
                is_idle: 0,
                tag_name: nil
            )]
        )
        try await app.test(.POST, "api/v1/sync/push", beforeRequest: { req in
            try req.content.encode(push)
        })

        // Pull as dev-1 — should see dev-2's logs
        try await app.test(.GET, "api/v1/sync/pull?device_id=dev-1&since=0", afterResponse: { res async in
            #expect(res.status == .ok)
            let body = try? res.content.decode(SyncPullResponse.self)
            #expect(body?.logs.count == 1)
            #expect(body?.logs.first?.device_name == "Mac Mini")
            #expect(body?.logs.first?.bundle_id == "com.apple.Safari")
        })

        // Pull as dev-2 — should NOT see own logs
        try await app.test(.GET, "api/v1/sync/pull?device_id=dev-2&since=0", afterResponse: { res async in
            let body = try? res.content.decode(SyncPullResponse.self)
            #expect(body?.logs.count == 0)
        })
    }

    @Test func pullRespectsTimestamp() async throws {
        let app = try await Application.make(.testing)
        try configure(app)
        defer { Task { try await app.asyncShutdown() } }

        try await app.test(.POST, "api/v1/devices", beforeRequest: { req in
            try req.content.encode(RegisterDeviceRequest(device_id: "dev-1", name: "MacBook"))
        })
        try await app.test(.POST, "api/v1/devices", beforeRequest: { req in
            try req.content.encode(RegisterDeviceRequest(device_id: "dev-2", name: "Mac Mini"))
        })

        let push = SyncPushRequest(
            device_id: "dev-2",
            apps: [AppPayload(bundle_id: "com.apple.Safari", app_name: "Safari")],
            tags: [],
            logs: [
                LogPayload(client_log_id: 1, bundle_id: "com.apple.Safari", window_title: "Old",
                           start_time: 1000.0, end_time: 1100.0, is_idle: 0, tag_name: nil),
                LogPayload(client_log_id: 2, bundle_id: "com.apple.Safari", window_title: "New",
                           start_time: 2000.0, end_time: 2100.0, is_idle: 0, tag_name: nil),
            ]
        )
        try await app.test(.POST, "api/v1/sync/push", beforeRequest: { req in
            try req.content.encode(push)
        })

        // Pull only logs after start_time 1500
        try await app.test(.GET, "api/v1/sync/pull?device_id=dev-1&since=1500", afterResponse: { res async in
            let body = try? res.content.decode(SyncPullResponse.self)
            #expect(body?.logs.count == 1)
            #expect(body?.logs.first?.window_title == "New")
        })
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd EmpTrackingServer && swift test --filter SyncPullTests`
Expected: FAIL (pull returns empty)

**Step 3: Implement pull in SyncController**

Replace the `pull` method in `SyncController.swift`:
```swift
@Sendable
func pull(req: Request) async throws -> SyncPullResponse {
    guard let deviceId = req.query[String.self, at: "device_id"],
          let since = req.query[Double.self, at: "since"] else {
        throw Abort(.badRequest, reason: "device_id and since are required")
    }

    let logs = try await ServerActivityLog.query(on: req.db)
        .filter(\.$deviceId != deviceId)
        .filter(\.$startTime >= since)
        .all()

    var payloads: [RemoteLogPayload] = []
    for log in logs {
        guard let app = try await TrackedApp.find(log.appId, on: req.db) else { continue }
        let device = try await Device.find(log.deviceId, on: req.db)

        var tagName: String? = nil
        if let tagId = log.tagId {
            tagName = try await TrackedTag.find(tagId, on: req.db)?.name
        }

        payloads.append(RemoteLogPayload(
            device_id: log.deviceId,
            device_name: device?.name ?? "Unknown",
            bundle_id: app.bundleId,
            app_name: app.appName,
            window_title: log.windowTitle,
            start_time: log.startTime,
            end_time: log.endTime,
            is_idle: log.isIdle,
            tag_name: tagName
        ))
    }

    return SyncPullResponse(
        logs: payloads,
        server_time: Date().timeIntervalSince1970
    )
}
```

**Step 4: Run tests**

Run: `cd EmpTrackingServer && swift test`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add EmpTrackingServer/
git commit -m "feat: add GET /sync/pull endpoint"
```

---

## Phase 2: Client Database Changes

### Task 6: Add settings table and device_id management

**Files:**
- Modify: `EmpTracking/Services/DatabaseManager.swift` (lines 22-87 initialize(), add new methods after line 598)
- Test: `EmpTrackingTests/EmpTrackingTests.swift`

**Step 1: Write the failing test**

Add to `EmpTrackingTests/EmpTrackingTests.swift`:
```swift
@Test func createsAndRetrievesDeviceId() throws {
    let db = try makeTestDB()

    let deviceId = try db.getOrCreateDeviceId()
    #expect(!deviceId.isEmpty)
    #expect(UUID(uuidString: deviceId) != nil)

    // Should return the same ID on second call
    let sameId = try db.getOrCreateDeviceId()
    #expect(sameId == deviceId)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme EmpTracking -destination 'platform=macOS' -only-testing:EmpTrackingTests/DatabaseManagerTests/createsAndRetrievesDeviceId 2>&1 | tail -20`
Expected: FAIL (method not found)

**Step 3: Add settings table to initialize()**

In `DatabaseManager.swift`, add after line 86 (end of icon migration), before closing `}` of `initialize()`:

```swift
// Migration: settings table for sync configuration
try execute("""
    CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    )
""")
```

**Step 4: Add helper methods**

Add before `enum DBError` (before line 601):

```swift
// MARK: - Settings

func saveSetting(key: String, value: String) throws {
    let sql = "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)"
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }

    sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
    sqlite3_bind_text(stmt, 2, (value as NSString).utf8String, -1, nil)

    if sqlite3_step(stmt) != SQLITE_DONE {
        throw DBError.insertFailed(String(cString: sqlite3_errmsg(db)))
    }
}

func fetchSetting(key: String) throws -> String? {
    let sql = "SELECT value FROM settings WHERE key = ?"
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }

    sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)

    if sqlite3_step(stmt) == SQLITE_ROW {
        return String(cString: sqlite3_column_text(stmt, 0))
    }
    return nil
}

func getOrCreateDeviceId() throws -> String {
    if let existing = try fetchSetting(key: "device_id") {
        return existing
    }
    let uuid = UUID().uuidString
    try saveSetting(key: "device_id", value: uuid)
    return uuid
}
```

**Step 5: Run test**

Run: `xcodebuild test -scheme EmpTracking -destination 'platform=macOS' -only-testing:EmpTrackingTests/DatabaseManagerTests/createsAndRetrievesDeviceId 2>&1 | tail -20`
Expected: PASS

**Step 6: Run all existing tests**

Run: `xcodebuild test -scheme EmpTracking -destination 'platform=macOS' 2>&1 | tail -20`
Expected: ALL PASS (no regressions)

**Step 7: Commit**

```bash
git add EmpTracking/Services/DatabaseManager.swift EmpTrackingTests/EmpTrackingTests.swift
git commit -m "feat: add settings table and device_id management"
```

---

### Task 7: Add synced column migration and remote_logs table

**Files:**
- Modify: `EmpTracking/Services/DatabaseManager.swift` (initialize())
- Test: `EmpTrackingTests/EmpTrackingTests.swift`

**Step 1: Write the failing test**

Add to `EmpTrackingTests/EmpTrackingTests.swift`:
```swift
@Test func unsyncedLogsDefaultToZero() throws {
    let db = try makeTestDB()
    let appId = try db.insertOrGetApp(bundleId: "com.test.app", appName: "TestApp")
    let now = Date()
    _ = try db.insertActivityLog(appId: appId, windowTitle: "W", startTime: now, endTime: now, isIdle: false)

    let unsynced = try db.fetchUnsyncedLogs(limit: 100)
    #expect(unsynced.count == 1)
}

@Test func markLogsAsSynced() throws {
    let db = try makeTestDB()
    let appId = try db.insertOrGetApp(bundleId: "com.test.app", appName: "TestApp")
    let now = Date()
    let logId = try db.insertActivityLog(appId: appId, windowTitle: "W", startTime: now, endTime: now, isIdle: false)

    try db.markLogsAsSynced(logIds: [logId])
    let unsynced = try db.fetchUnsyncedLogs(limit: 100)
    #expect(unsynced.isEmpty)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme EmpTracking -destination 'platform=macOS' -only-testing:EmpTrackingTests/DatabaseManagerTests/unsyncedLogsDefaultToZero 2>&1 | tail -20`
Expected: FAIL (fetchUnsyncedLogs not found)

**Step 3: Add migration in initialize()**

In `DatabaseManager.swift`, add after the settings table migration:

```swift
// Migration: add synced column for sync tracking
let logsColumns2 = try fetchColumnNames(table: "activity_logs")
if !logsColumns2.contains("synced") {
    try execute("ALTER TABLE activity_logs ADD COLUMN synced INTEGER DEFAULT 0")
}

// Remote logs table for data from other devices
try execute("""
    CREATE TABLE IF NOT EXISTS remote_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        device_name TEXT NOT NULL,
        app_name TEXT NOT NULL,
        bundle_id TEXT NOT NULL,
        window_title TEXT,
        start_time REAL NOT NULL,
        end_time REAL NOT NULL,
        is_idle INTEGER NOT NULL DEFAULT 0,
        tag_name TEXT
    )
""")
```

**Step 4: Add fetchUnsyncedLogs and markLogsAsSynced**

Add to `DatabaseManager.swift` in the MARK: - Settings section:

```swift
// MARK: - Sync

func fetchUnsyncedLogs(limit: Int) throws -> [(log: ActivityLog, bundleId: String, tagName: String?)] {
    let sql = """
        SELECT l.id, l.app_id, l.window_title, l.start_time, l.end_time, l.is_idle, l.tag_id,
               a.bundle_id,
               t.name as tag_name
        FROM activity_logs l
        JOIN apps a ON a.id = l.app_id
        LEFT JOIN tags t ON t.id = COALESCE(l.tag_id, a.default_tag_id)
        WHERE l.synced = 0
        ORDER BY l.id
        LIMIT ?
    """
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }

    sqlite3_bind_int(stmt, 1, Int32(limit))

    var results: [(log: ActivityLog, bundleId: String, tagName: String?)] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        let log = ActivityLog(
            id: sqlite3_column_int64(stmt, 0),
            appId: sqlite3_column_int64(stmt, 1),
            windowTitle: sqlite3_column_type(stmt, 2) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 2)) : nil,
            startTime: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
            endTime: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
            isIdle: sqlite3_column_int(stmt, 5) != 0,
            tagId: sqlite3_column_type(stmt, 6) != SQLITE_NULL
                ? sqlite3_column_int64(stmt, 6) : nil
        )
        let bundleId = String(cString: sqlite3_column_text(stmt, 7))
        let tagName: String? = sqlite3_column_type(stmt, 8) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 8)) : nil
        results.append((log: log, bundleId: bundleId, tagName: tagName))
    }
    return results
}

func markLogsAsSynced(logIds: [Int64]) throws {
    guard !logIds.isEmpty else { return }
    let placeholders = logIds.map { _ in "?" }.joined(separator: ",")
    let sql = "UPDATE activity_logs SET synced = 1 WHERE id IN (\(placeholders))"
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }

    for (i, id) in logIds.enumerated() {
        sqlite3_bind_int64(stmt, Int32(i + 1), id)
    }

    if sqlite3_step(stmt) != SQLITE_DONE {
        throw DBError.updateFailed(String(cString: sqlite3_errmsg(db)))
    }
}

func insertRemoteLog(deviceId: String, deviceName: String, appName: String, bundleId: String,
                     windowTitle: String?, startTime: Double, endTime: Double,
                     isIdle: Bool, tagName: String?) throws {
    let sql = """
        INSERT INTO remote_logs (device_id, device_name, app_name, bundle_id,
                                 window_title, start_time, end_time, is_idle, tag_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }

    sqlite3_bind_text(stmt, 1, (deviceId as NSString).utf8String, -1, nil)
    sqlite3_bind_text(stmt, 2, (deviceName as NSString).utf8String, -1, nil)
    sqlite3_bind_text(stmt, 3, (appName as NSString).utf8String, -1, nil)
    sqlite3_bind_text(stmt, 4, (bundleId as NSString).utf8String, -1, nil)
    if let title = windowTitle {
        sqlite3_bind_text(stmt, 5, (title as NSString).utf8String, -1, nil)
    } else {
        sqlite3_bind_null(stmt, 5)
    }
    sqlite3_bind_double(stmt, 6, startTime)
    sqlite3_bind_double(stmt, 7, endTime)
    sqlite3_bind_int(stmt, 8, isIdle ? 1 : 0)
    if let tagName = tagName {
        sqlite3_bind_text(stmt, 9, (tagName as NSString).utf8String, -1, nil)
    } else {
        sqlite3_bind_null(stmt, 9)
    }

    if sqlite3_step(stmt) != SQLITE_DONE {
        throw DBError.insertFailed(String(cString: sqlite3_errmsg(db)))
    }
}

func clearRemoteLogsForDevice(_ deviceId: String) throws {
    try execute("DELETE FROM remote_logs WHERE device_id = '\(deviceId)'")
}

func fetchRemoteLogs(from: Date, to: Date) throws -> [RemoteLog] {
    let sql = """
        SELECT id, device_id, device_name, app_name, bundle_id, window_title,
               start_time, end_time, is_idle, tag_name
        FROM remote_logs
        WHERE start_time >= ? AND start_time < ?
        ORDER BY start_time DESC
    """
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }

    sqlite3_bind_double(stmt, 1, from.timeIntervalSince1970)
    sqlite3_bind_double(stmt, 2, to.timeIntervalSince1970)

    var logs: [RemoteLog] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        logs.append(RemoteLog(
            id: sqlite3_column_int64(stmt, 0),
            deviceId: String(cString: sqlite3_column_text(stmt, 1)),
            deviceName: String(cString: sqlite3_column_text(stmt, 2)),
            appName: String(cString: sqlite3_column_text(stmt, 3)),
            bundleId: String(cString: sqlite3_column_text(stmt, 4)),
            windowTitle: sqlite3_column_type(stmt, 5) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 5)) : nil,
            startTime: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6)),
            endTime: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
            isIdle: sqlite3_column_int(stmt, 8) != 0,
            tagName: sqlite3_column_type(stmt, 9) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 9)) : nil
        ))
    }
    return logs
}
```

**Step 5: Create RemoteLog model**

Create `EmpTracking/Models/RemoteLog.swift`:
```swift
import Foundation

struct RemoteLog {
    let id: Int64
    let deviceId: String
    let deviceName: String
    let appName: String
    let bundleId: String
    let windowTitle: String?
    let startTime: Date
    let endTime: Date
    let isIdle: Bool
    let tagName: String?
}
```

**Step 6: Run tests**

Run: `xcodebuild test -scheme EmpTracking -destination 'platform=macOS' 2>&1 | tail -20`
Expected: ALL PASS

**Step 7: Commit**

```bash
git add EmpTracking/Services/DatabaseManager.swift EmpTracking/Models/RemoteLog.swift EmpTrackingTests/
git commit -m "feat: add synced column, remote_logs table, and sync DB methods"
```

---

## Phase 3: SyncManager

### Task 8: Create SyncManager with push/pull

**Files:**
- Create: `EmpTracking/Services/SyncManager.swift`

**Step 1: Write SyncManager**

`EmpTracking/Services/SyncManager.swift`:
```swift
import Foundation

final class SyncManager {
    private let db: DatabaseManager
    private let serverBaseUrl: String
    private let deviceId: String
    private let deviceName: String
    private var timer: Timer?
    private let session: URLSession

    var onSyncCompleted: (() -> Void)?

    enum SyncError: Error {
        case serverUnreachable
        case httpError(Int)
        case invalidResponse
    }

    init(db: DatabaseManager) throws {
        self.db = db
        self.serverBaseUrl = UserDefaults.standard.string(forKey: "syncServerUrl")
            ?? "http://macmini.local:8080"
        self.deviceId = try db.getOrCreateDeviceId()
        self.deviceName = Host.current().localizedName ?? "Unknown Mac"

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.performSync()
        }
        // Initial sync after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.performSync()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func performSync() {
        Task {
            do {
                guard try await isServerReachable() else { return }
                try await registerDevice()
                try await pushUnsyncedLogs()
                try await pullRemoteLogs()
                await MainActor.run { onSyncCompleted?() }
            } catch {
                print("[Sync] Error: \(error)")
            }
        }
    }

    private func isServerReachable() async throws -> Bool {
        var request = URLRequest(url: URL(string: "\(serverBaseUrl)/health")!)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3

        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func registerDevice() async throws {
        let url = URL(string: "\(serverBaseUrl)/api/v1/devices")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["device_id": deviceId, "name": deviceName]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201 else {
            throw SyncError.httpError(status)
        }
    }

    private func pushUnsyncedLogs() async throws {
        let unsynced = try db.fetchUnsyncedLogs(limit: 100)
        guard !unsynced.isEmpty else { return }

        var appsSet = Set<String>()
        var apps: [[String: String]] = []
        var tagsSet = Set<String>()
        var tags: [[String: String]] = []
        var logs: [[String: Any]] = []

        for entry in unsynced {
            if appsSet.insert(entry.bundleId).inserted {
                // Fetch app name from DB
                if let appInfo = try db.fetchAppInfo(appId: entry.log.appId) {
                    apps.append(["bundle_id": entry.bundleId, "app_name": appInfo.appName])
                }
            }

            if let tagName = entry.tagName, tagsSet.insert(tagName).inserted {
                // Fetch tag colors
                let allTags = try db.fetchAllTags()
                if let tag = allTags.first(where: { $0.name == tagName }) {
                    tags.append([
                        "name": tag.name,
                        "color_light": tag.colorLight,
                        "color_dark": tag.colorDark
                    ])
                }
            }

            var logDict: [String: Any] = [
                "client_log_id": entry.log.id,
                "bundle_id": entry.bundleId,
                "start_time": entry.log.startTime.timeIntervalSince1970,
                "end_time": entry.log.endTime.timeIntervalSince1970,
                "is_idle": entry.log.isIdle ? 1 : 0,
            ]
            logDict["window_title"] = entry.log.windowTitle
            logDict["tag_name"] = entry.tagName
            logs.append(logDict)
        }

        let payload: [String: Any] = [
            "device_id": deviceId,
            "apps": apps,
            "tags": tags,
            "logs": logs
        ]

        let url = URL(string: "\(serverBaseUrl)/api/v1/sync/push")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SyncError.httpError(status) }

        try db.markLogsAsSynced(logIds: unsynced.map { $0.log.id })
        print("[Sync] Pushed \(unsynced.count) logs")
    }

    private func pullRemoteLogs() async throws {
        let lastSync = (try db.fetchSetting(key: "last_pull_time"))
            .flatMap { Double($0) } ?? 0

        let url = URL(string: "\(serverBaseUrl)/api/v1/sync/pull?device_id=\(deviceId)&since=\(lastSync)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SyncError.httpError(status) }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let logsArray = json["logs"] as? [[String: Any]],
              let serverTime = json["server_time"] as? Double else {
            throw SyncError.invalidResponse
        }

        for entry in logsArray {
            try db.insertRemoteLog(
                deviceId: entry["device_id"] as? String ?? "",
                deviceName: entry["device_name"] as? String ?? "",
                appName: entry["app_name"] as? String ?? "",
                bundleId: entry["bundle_id"] as? String ?? "",
                windowTitle: entry["window_title"] as? String,
                startTime: entry["start_time"] as? Double ?? 0,
                endTime: entry["end_time"] as? Double ?? 0,
                isIdle: (entry["is_idle"] as? Int ?? 0) != 0,
                tagName: entry["tag_name"] as? String
            )
        }

        if !logsArray.isEmpty {
            print("[Sync] Pulled \(logsArray.count) remote logs")
        }
        try db.saveSetting(key: "last_pull_time", value: String(serverTime))
    }
}
```

**Step 2: Build**

Run: `xcodebuild build -scheme EmpTracking -destination 'platform=macOS' 2>&1 | tail -10`
Expected: Build succeeds

**Step 3: Run all tests**

Run: `xcodebuild test -scheme EmpTracking -destination 'platform=macOS' 2>&1 | tail -20`
Expected: ALL PASS

**Step 4: Commit**

```bash
git add EmpTracking/Services/SyncManager.swift
git commit -m "feat: add SyncManager with push/pull sync logic"
```

---

## Phase 4: Wire Everything Together

### Task 9: Wire SyncManager into AppDelegate

**Files:**
- Modify: `EmpTracking/AppDelegate.swift`

**Step 1: Add SyncManager property and setup**

In `AppDelegate.swift`, add after `private var detailWindow: NSWindow?` (line 11):
```swift
private var syncManager: SyncManager?
```

Add call in `applicationDidFinishLaunching` after `setupTracker()` (line 23):
```swift
setupSync()
```

Add new method after `setupTracker()` (after line 76):
```swift
private func setupSync() {
    do {
        syncManager = try SyncManager(db: db)
        syncManager?.onSyncCompleted = { [weak self] in
            if self?.popover.isShown == true {
                self?.timelineVC.reload()
            }
        }
        syncManager?.start()
    } catch {
        print("Failed to start sync: \(error)")
    }
}
```

Add to `applicationWillTerminate` (line 28):
```swift
syncManager?.stop()
```

**Step 2: Build**

Run: `xcodebuild build -scheme EmpTracking -destination 'platform=macOS' 2>&1 | tail -10`
Expected: Build succeeds

**Step 3: Run all tests**

Run: `xcodebuild test -scheme EmpTracking -destination 'platform=macOS' 2>&1 | tail -20`
Expected: ALL PASS

**Step 4: Commit**

```bash
git add EmpTracking/AppDelegate.swift
git commit -m "feat: wire SyncManager into AppDelegate"
```

---

### Task 10: Add device filter to DetailViewController

**Files:**
- Modify: `EmpTracking/Views/DetailViewController.swift`

This task adds a segmented control to filter data by device (All / This Mac / Other Macs). The exact implementation depends on the current DetailViewController layout. The core changes are:

**Step 1: Read current DetailViewController**

Read the file to understand current layout before modifying.

**Step 2: Add filter enum and state**

Add to class properties:
```swift
private enum DeviceFilter: Int { case all = 0, thisMac = 1, otherMacs = 2 }
private var deviceFilter: DeviceFilter = .all
private let deviceFilterControl = NSSegmentedControl()
private let deviceId: String
```

Update init to accept deviceId:
```swift
init(db: DatabaseManager, deviceId: String) {
    self.deviceId = deviceId
    // ... existing init
}
```

**Step 3: Add filter control to UI**

In `loadView()` or equivalent, add the segmented control:
```swift
deviceFilterControl.segmentCount = 3
deviceFilterControl.setLabel("Все", forSegment: 0)
deviceFilterControl.setLabel("Этот Mac", forSegment: 1)
deviceFilterControl.setLabel("Другие", forSegment: 2)
deviceFilterControl.selectedSegment = 0
deviceFilterControl.target = self
deviceFilterControl.action = #selector(deviceFilterChanged(_:))
```

**Step 4: Add filter handler**

```swift
@objc private func deviceFilterChanged(_ sender: NSSegmentedControl) {
    deviceFilter = DeviceFilter(rawValue: sender.selectedSegment) ?? .all
    reload()
}
```

**Step 5: Modify data loading to include remote_logs**

When `deviceFilter == .all` or `.otherMacs`, also fetch from `remote_logs` table and merge with local data. When `.thisMac`, only show local data.

**Step 6: Update AppDelegate to pass deviceId**

In `AppDelegate.swift`, change `DetailViewController(db: db)` to:
```swift
let deviceId = (try? db.getOrCreateDeviceId()) ?? ""
let detailVC = DetailViewController(db: db, deviceId: deviceId)
```

**Step 7: Build and test**

Run: `xcodebuild build -scheme EmpTracking -destination 'platform=macOS' 2>&1 | tail -10`
Expected: Build succeeds

**Step 8: Commit**

```bash
git add EmpTracking/Views/DetailViewController.swift EmpTracking/AppDelegate.swift
git commit -m "feat: add device filter to DetailViewController"
```

---

## Phase 5: Server Deployment

### Task 11: Create LaunchAgent for server

**Files:**
- Create: `EmpTrackingServer/deploy/com.emptracking.server.plist`
- Create: `EmpTrackingServer/deploy/install.sh`

**Step 1: Create plist**

`EmpTrackingServer/deploy/com.emptracking.server.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.emptracking.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>__BINARY_PATH__</string>
        <string>serve</string>
        <string>--hostname</string>
        <string>0.0.0.0</string>
        <string>--port</string>
        <string>8080</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>__LOG_DIR__/server.log</string>
    <key>StandardErrorPath</key>
    <string>__LOG_DIR__/server.log</string>
    <key>WorkingDirectory</key>
    <string>__WORKING_DIR__</string>
</dict>
</plist>
```

**Step 2: Create install script**

`EmpTrackingServer/deploy/install.sh`:
```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_DIR="$HOME/EmpTrackingServer"
LOG_DIR="$HOME/Library/Logs/EmpTracking"
PLIST_NAME="com.emptracking.server"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

echo "Building server..."
cd "$SERVER_DIR"
swift build -c release

echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp -f ".build/release/App" "$INSTALL_DIR/EmpTrackingServer"
mkdir -p "$LOG_DIR"

echo "Installing LaunchAgent..."
# Stop existing if running
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true

sed -e "s|__BINARY_PATH__|$INSTALL_DIR/EmpTrackingServer|g" \
    -e "s|__LOG_DIR__|$LOG_DIR|g" \
    -e "s|__WORKING_DIR__|$INSTALL_DIR|g" \
    "$SCRIPT_DIR/com.emptracking.server.plist" > "$PLIST_DEST"

launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST"

echo "Done! Server running on http://$(hostname).local:8080"
echo "Logs: $LOG_DIR/server.log"
```

**Step 3: Make executable and commit**

```bash
chmod +x EmpTrackingServer/deploy/install.sh
git add EmpTrackingServer/deploy/
git commit -m "feat: add LaunchAgent deployment for server"
```

---

## Summary

| Phase | Tasks | Description |
|-------|-------|-------------|
| 1 | 1-5 | Vapor server (scaffold, models, endpoints) |
| 2 | 6-7 | Client DB migrations and sync methods |
| 3 | 8 | SyncManager service |
| 4 | 9-10 | AppDelegate wiring + UI device filter |
| 5 | 11 | Server deployment |

**Total: 11 tasks, ~55 bite-sized steps**

**Dependencies:**
- Phase 1 (server) and Phase 2 (client DB) can be done in parallel
- Phase 3 depends on Phase 2
- Phase 4 depends on Phase 3
- Phase 5 depends on Phase 1
