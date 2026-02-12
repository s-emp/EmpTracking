import Foundation
import SQLite3
import Cocoa

nonisolated final class DatabaseManager: @unchecked Sendable {
    private var db: OpaquePointer?
    private let path: String

    init(path: String) {
        self.path = path
    }

    deinit {
        sqlite3_close(db)
    }

    func initialize() throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        if sqlite3_open(path, &db) != SQLITE_OK {
            throw DBError.cannotOpen(String(cString: sqlite3_errmsg(db)))
        }

        try execute("""
            CREATE TABLE IF NOT EXISTS apps (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                bundle_id TEXT UNIQUE,
                app_name TEXT NOT NULL,
                icon BLOB
            )
        """)

        try execute("""
            CREATE TABLE IF NOT EXISTS activity_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                app_id INTEGER REFERENCES apps(id),
                window_title TEXT,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                is_idle INTEGER DEFAULT 0
            )
        """)
    }

    func insertOrGetApp(bundleId: String, appName: String, iconPNG: Data?) throws -> Int64 {
        let query = "SELECT id FROM apps WHERE bundle_id = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (bundleId as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_int64(stmt, 0)
            }
        }
        sqlite3_finalize(stmt)
        stmt = nil

        let insert = "INSERT INTO apps (bundle_id, app_name, icon) VALUES (?, ?, ?)"
        if sqlite3_prepare_v2(db, insert, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (bundleId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (appName as NSString).utf8String, -1, nil)
            if let iconData = iconPNG {
                _ = iconData.withUnsafeBytes { rawBuffer in
                    sqlite3_bind_blob(stmt, 3, rawBuffer.baseAddress, Int32(iconData.count), nil)
                }
            } else {
                sqlite3_bind_null(stmt, 3)
            }

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DBError.insertFailed(String(cString: sqlite3_errmsg(db)))
            }
        }

        return sqlite3_last_insert_rowid(db)
    }

    func insertActivityLog(appId: Int64, windowTitle: String?, startTime: Date, endTime: Date, isIdle: Bool) throws -> Int64 {
        let sql = "INSERT INTO activity_logs (app_id, window_title, start_time, end_time, is_idle) VALUES (?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int64(stmt, 1, appId)
        if let title = windowTitle {
            sqlite3_bind_text(stmt, 2, (title as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_double(stmt, 3, startTime.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 4, endTime.timeIntervalSince1970)
        sqlite3_bind_int(stmt, 5, isIdle ? 1 : 0)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DBError.insertFailed(String(cString: sqlite3_errmsg(db)))
        }

        return sqlite3_last_insert_rowid(db)
    }

    func updateEndTime(logId: Int64, endTime: Date) throws {
        let sql = "UPDATE activity_logs SET end_time = ? WHERE id = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_double(stmt, 1, endTime.timeIntervalSince1970)
        sqlite3_bind_int64(stmt, 2, logId)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DBError.updateFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func fetchLastLog() throws -> ActivityLog? {
        let sql = "SELECT id, app_id, window_title, start_time, end_time, is_idle FROM activity_logs ORDER BY id DESC LIMIT 1"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return logFromStatement(stmt!)
        }

        return nil
    }

    func fetchTodayLogs() throws -> [ActivityLog] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date()).timeIntervalSince1970

        let sql = "SELECT id, app_id, window_title, start_time, end_time, is_idle FROM activity_logs WHERE start_time >= ? ORDER BY start_time DESC"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_double(stmt, 1, startOfDay)

        var logs: [ActivityLog] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            logs.append(logFromStatement(stmt!))
        }

        return logs
    }

    func fetchAppSummaries(since: Date) throws -> [AppSummary] {
        let sql = """
            SELECT a.id, a.app_name, a.bundle_id, a.icon,
                   SUM(l.end_time - l.start_time) as total_duration
            FROM activity_logs l
            JOIN apps a ON a.id = l.app_id
            WHERE l.start_time >= ? AND l.is_idle = 0
            GROUP BY l.app_id
            ORDER BY total_duration DESC
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_double(stmt, 1, since.timeIntervalSince1970)

        var summaries: [AppSummary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let appId = sqlite3_column_int64(stmt, 0)
            let appName = String(cString: sqlite3_column_text(stmt, 1))
            let bundleId = String(cString: sqlite3_column_text(stmt, 2))

            var icon: NSImage? = nil
            if sqlite3_column_type(stmt, 3) != SQLITE_NULL {
                let bytes = sqlite3_column_blob(stmt, 3)
                let length = sqlite3_column_bytes(stmt, 3)
                if let bytes = bytes, length > 0 {
                    let data = Data(bytes: bytes, count: Int(length))
                    icon = NSImage(data: data)
                }
            }

            let totalDuration = sqlite3_column_double(stmt, 4)
            summaries.append(AppSummary(appId: appId, appName: appName, bundleId: bundleId, icon: icon, totalDuration: totalDuration))
        }

        return summaries
    }

    func fetchAppInfo(appId: Int64) throws -> AppInfo? {
        let sql = "SELECT id, bundle_id, app_name, icon FROM apps WHERE id = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int64(stmt, 1, appId)

        if sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let bundleId = String(cString: sqlite3_column_text(stmt, 1))
            let appName = String(cString: sqlite3_column_text(stmt, 2))

            var icon: NSImage? = nil
            if sqlite3_column_type(stmt, 3) != SQLITE_NULL {
                let bytes = sqlite3_column_blob(stmt, 3)
                let length = sqlite3_column_bytes(stmt, 3)
                if let bytes = bytes, length > 0 {
                    let data = Data(bytes: bytes, count: Int(length))
                    icon = NSImage(data: data)
                }
            }

            return AppInfo(id: id, bundleId: bundleId, appName: appName, icon: icon)
        }

        return nil
    }

    private func logFromStatement(_ stmt: OpaquePointer) -> ActivityLog {
        let id = sqlite3_column_int64(stmt, 0)
        let appId = sqlite3_column_int64(stmt, 1)
        let windowTitle: String? = sqlite3_column_type(stmt, 2) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 2)) : nil
        let startTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
        let endTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
        let isIdle = sqlite3_column_int(stmt, 5) != 0

        return ActivityLog(id: id, appId: appId, windowTitle: windowTitle, startTime: startTime, endTime: endTime, isIdle: isIdle)
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(error)
            throw DBError.execFailed(message)
        }
    }

    enum DBError: Error {
        case cannotOpen(String)
        case execFailed(String)
        case prepareFailed(String)
        case insertFailed(String)
        case updateFailed(String)
    }
}
