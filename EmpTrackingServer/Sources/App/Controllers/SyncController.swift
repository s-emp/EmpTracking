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

        // Upsert apps by bundle_id
        for appPayload in input.apps {
            let existing = try await TrackedApp.query(on: req.db)
                .filter(\.$bundleId == appPayload.bundle_id)
                .first()
            if let existing {
                existing.appName = appPayload.app_name
                try await existing.save(on: req.db)
            } else {
                let app = TrackedApp(bundleId: appPayload.bundle_id, appName: appPayload.app_name)
                try await app.save(on: req.db)
            }
        }

        // Upsert tags by name
        for tagPayload in input.tags {
            let existing = try await TrackedTag.query(on: req.db)
                .filter(\.$name == tagPayload.name)
                .first()
            if let existing {
                existing.colorLight = tagPayload.color_light
                existing.colorDark = tagPayload.color_dark
                try await existing.save(on: req.db)
            } else {
                let tag = TrackedTag(
                    name: tagPayload.name,
                    colorLight: tagPayload.color_light,
                    colorDark: tagPayload.color_dark
                )
                try await tag.save(on: req.db)
            }
        }

        // Insert activity logs, skipping duplicates
        var syncedCount = 0
        for logPayload in input.logs {
            // Check for duplicate by device_id + client_log_id
            let duplicate = try await ServerActivityLog.query(on: req.db)
                .filter(\.$deviceId == input.device_id)
                .filter(\.$clientLogId == logPayload.client_log_id)
                .first()
            if duplicate != nil { continue }

            // Resolve bundle_id to app_id
            guard let app = try await TrackedApp.query(on: req.db)
                .filter(\.$bundleId == logPayload.bundle_id)
                .first(),
                let appId = app.id else {
                continue
            }

            // Resolve tag_name to tag_id
            var tagId: Int? = nil
            if let tagName = logPayload.tag_name {
                let tag = try await TrackedTag.query(on: req.db)
                    .filter(\.$name == tagName)
                    .first()
                tagId = tag?.id
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
        let deviceId = try req.query.get(String.self, at: "device_id")
        let since = try req.query.get(Double.self, at: "since")

        // Fetch logs from OTHER devices where start_time >= since
        let logs = try await ServerActivityLog.query(on: req.db)
            .filter(\.$deviceId != deviceId)
            .filter(\.$startTime >= since)
            .all()

        // Build response payloads with joined data
        var remoteLogs: [RemoteLogPayload] = []
        for log in logs {
            guard let app = try await TrackedApp.find(log.appId, on: req.db) else { continue }
            guard let device = try await Device.find(log.deviceId, on: req.db) else { continue }

            var tagName: String? = nil
            if let tagId = log.tagId {
                let tag = try await TrackedTag.find(tagId, on: req.db)
                tagName = tag?.name
            }

            remoteLogs.append(RemoteLogPayload(
                device_id: log.deviceId,
                device_name: device.name,
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
            logs: remoteLogs,
            server_time: Date().timeIntervalSince1970
        )
    }
}
