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
                if let appInfo = try db.fetchAppInfo(appId: entry.log.appId) {
                    apps.append(["bundle_id": entry.bundleId, "app_name": appInfo.appName])
                }
            }

            if let tagName = entry.tagName, tagsSet.insert(tagName).inserted {
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
