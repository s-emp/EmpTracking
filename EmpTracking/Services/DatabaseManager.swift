import Foundation
import SQLite3
import Cocoa

struct TagSlotDuration {
    let tagId: Int64?
    let duration: TimeInterval
}

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

        try execute("""
            CREATE TABLE IF NOT EXISTS tags (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                color_light TEXT NOT NULL,
                color_dark TEXT NOT NULL
            )
        """)

        // Migration: add tag columns to existing tables
        let appsColumns = try fetchColumnNames(table: "apps")
        if !appsColumns.contains("default_tag_id") {
            try execute("ALTER TABLE apps ADD COLUMN default_tag_id INTEGER REFERENCES tags(id)")
        }

        let logsColumns = try fetchColumnNames(table: "activity_logs")
        if !logsColumns.contains("tag_id") {
            try execute("ALTER TABLE activity_logs ADD COLUMN tag_id INTEGER REFERENCES tags(id)")
        }
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
        let sql = "SELECT id, app_id, window_title, start_time, end_time, is_idle, tag_id FROM activity_logs ORDER BY id DESC LIMIT 1"
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

        let sql = "SELECT id, app_id, window_title, start_time, end_time, is_idle, tag_id FROM activity_logs WHERE start_time >= ? ORDER BY start_time DESC"
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
        let sql = "SELECT id, bundle_id, app_name, icon, default_tag_id FROM apps WHERE id = ?"
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

            let defaultTagId: Int64? = sqlite3_column_type(stmt, 4) != SQLITE_NULL
                ? sqlite3_column_int64(stmt, 4) : nil
            return AppInfo(id: id, bundleId: bundleId, appName: appName, icon: icon, defaultTagId: defaultTagId)
        }

        return nil
    }

    // MARK: - Tag CRUD

    func createTag(name: String, colorLight: String, colorDark: String) throws -> Tag {
        let sql = "INSERT INTO tags (name, color_light, color_dark) VALUES (?, ?, ?)"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (colorLight as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (colorDark as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DBError.insertFailed(String(cString: sqlite3_errmsg(db)))
        }

        let id = sqlite3_last_insert_rowid(db)
        return Tag(id: id, name: name, colorLight: colorLight, colorDark: colorDark)
    }

    func fetchAllTags() throws -> [Tag] {
        let sql = "SELECT id, name, color_light, color_dark FROM tags ORDER BY name"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        var tags: [Tag] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            tags.append(tagFromStatement(stmt!))
        }
        return tags
    }

    func updateTag(id: Int64, name: String, colorLight: String, colorDark: String) throws {
        let sql = "UPDATE tags SET name = ?, color_light = ?, color_dark = ? WHERE id = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (colorLight as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (colorDark as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 4, id)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DBError.updateFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func deleteTag(id: Int64) throws {
        try execute("UPDATE apps SET default_tag_id = NULL WHERE default_tag_id = \(id)")
        try execute("UPDATE activity_logs SET tag_id = NULL WHERE tag_id = \(id)")
        try execute("DELETE FROM tags WHERE id = \(id)")
    }

    private func tagFromStatement(_ stmt: OpaquePointer) -> Tag {
        let id = sqlite3_column_int64(stmt, 0)
        let name = String(cString: sqlite3_column_text(stmt, 1))
        let colorLight = String(cString: sqlite3_column_text(stmt, 2))
        let colorDark = String(cString: sqlite3_column_text(stmt, 3))
        return Tag(id: id, name: name, colorLight: colorLight, colorDark: colorDark)
    }

    func setDefaultTag(appId: Int64, tagId: Int64?) throws {
        let sql = "UPDATE apps SET default_tag_id = ? WHERE id = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        if let tagId = tagId {
            sqlite3_bind_int64(stmt, 1, tagId)
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        sqlite3_bind_int64(stmt, 2, appId)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DBError.updateFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func setSessionTag(logId: Int64, tagId: Int64?) throws {
        let sql = "UPDATE activity_logs SET tag_id = ? WHERE id = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        if let tagId = tagId {
            sqlite3_bind_int64(stmt, 1, tagId)
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        sqlite3_bind_int64(stmt, 2, logId)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DBError.updateFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func fetchTagSummaries(from: Date, to: Date) throws -> [TagSummary] {
        let sql = """
            SELECT t.id, t.name, t.color_light, t.color_dark,
                   SUM(l.end_time - l.start_time) as total_duration
            FROM activity_logs l
            JOIN apps a ON a.id = l.app_id
            LEFT JOIN tags t ON t.id = COALESCE(l.tag_id, a.default_tag_id)
            WHERE l.start_time >= ? AND l.end_time <= ? AND l.is_idle = 0
            GROUP BY COALESCE(l.tag_id, a.default_tag_id)
            ORDER BY total_duration DESC
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_double(stmt, 1, from.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 2, to.timeIntervalSince1970)

        var summaries: [TagSummary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let tag: Tag?
            if sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                tag = Tag(
                    id: sqlite3_column_int64(stmt, 0),
                    name: String(cString: sqlite3_column_text(stmt, 1)),
                    colorLight: String(cString: sqlite3_column_text(stmt, 2)),
                    colorDark: String(cString: sqlite3_column_text(stmt, 3))
                )
            } else {
                tag = nil
            }
            let totalDuration = sqlite3_column_double(stmt, 4)
            summaries.append(TagSummary(tag: tag, totalDuration: totalDuration))
        }
        return summaries
    }

    func fetchHourlyTagSummaries(for date: Date) throws -> [Int: [TagSlotDuration]] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay = startOfDay.addingTimeInterval(86400)

        let sql = """
            SELECT CAST(strftime('%H', l.start_time, 'unixepoch', 'localtime') AS INTEGER) as hour,
                   COALESCE(l.tag_id, a.default_tag_id) as resolved_tag_id,
                   SUM(l.end_time - l.start_time) as total_duration
            FROM activity_logs l
            JOIN apps a ON a.id = l.app_id
            WHERE l.start_time >= ? AND l.start_time < ? AND l.is_idle = 0
            GROUP BY hour, resolved_tag_id
            ORDER BY hour, total_duration DESC
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_double(stmt, 1, startOfDay.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 2, endOfDay.timeIntervalSince1970)

        var result: [Int: [TagSlotDuration]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let hour = Int(sqlite3_column_int(stmt, 0))
            let tagId: Int64? = sqlite3_column_type(stmt, 1) != SQLITE_NULL
                ? sqlite3_column_int64(stmt, 1) : nil
            let duration = sqlite3_column_double(stmt, 2)
            result[hour, default: []].append(TagSlotDuration(tagId: tagId, duration: duration))
        }
        return result
    }

    private func logFromStatement(_ stmt: OpaquePointer) -> ActivityLog {
        let id = sqlite3_column_int64(stmt, 0)
        let appId = sqlite3_column_int64(stmt, 1)
        let windowTitle: String? = sqlite3_column_type(stmt, 2) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 2)) : nil
        let startTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
        let endTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
        let isIdle = sqlite3_column_int(stmt, 5) != 0
        let tagId: Int64? = sqlite3_column_type(stmt, 6) != SQLITE_NULL
            ? sqlite3_column_int64(stmt, 6) : nil

        return ActivityLog(id: id, appId: appId, windowTitle: windowTitle, startTime: startTime, endTime: endTime, isIdle: isIdle, tagId: tagId)
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(error)
            throw DBError.execFailed(message)
        }
    }

    private func fetchColumnNames(table: String) throws -> [String] {
        let sql = "PRAGMA table_info(\(table))"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        var names: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cStr = sqlite3_column_text(stmt, 1) {
                names.append(String(cString: cStr))
            }
        }
        return names
    }

    enum DBError: Error {
        case cannotOpen(String)
        case execFailed(String)
        case prepareFailed(String)
        case insertFailed(String)
        case updateFailed(String)
    }
}
