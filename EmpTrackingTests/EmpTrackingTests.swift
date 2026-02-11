import Testing
import Foundation
@testable import EmpTracking

struct DatabaseManagerTests {

    @Test func createsDatabaseFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("test.db").path
        let db = DatabaseManager(path: dbPath)
        try db.initialize()

        #expect(FileManager.default.fileExists(atPath: dbPath))
    }

    @Test func insertsAndRetrievesApp() throws {
        let db = try makeTestDB()

        let appId = try db.insertOrGetApp(bundleId: "com.test.app", appName: "TestApp", iconPNG: nil)
        #expect(appId > 0)

        let sameId = try db.insertOrGetApp(bundleId: "com.test.app", appName: "TestApp", iconPNG: nil)
        #expect(sameId == appId)
    }

    @Test func insertsAndUpdatesActivityLog() throws {
        let db = try makeTestDB()

        let appId = try db.insertOrGetApp(bundleId: "com.test.app", appName: "TestApp", iconPNG: nil)
        let now = Date()

        let logId = try db.insertActivityLog(
            appId: appId,
            windowTitle: "Test Window",
            startTime: now,
            endTime: now,
            isIdle: false
        )
        #expect(logId > 0)

        let later = now.addingTimeInterval(30)
        try db.updateEndTime(logId: logId, endTime: later)

        let logs = try db.fetchTodayLogs()
        #expect(logs.count == 1)
        #expect(logs[0].windowTitle == "Test Window")
    }

    @Test func fetchesLastLog() throws {
        let db = try makeTestDB()

        let appId = try db.insertOrGetApp(bundleId: "com.test.app", appName: "TestApp", iconPNG: nil)
        let now = Date()

        _ = try db.insertActivityLog(appId: appId, windowTitle: "First", startTime: now, endTime: now, isIdle: false)
        let secondId = try db.insertActivityLog(appId: appId, windowTitle: "Second", startTime: now.addingTimeInterval(10), endTime: now.addingTimeInterval(10), isIdle: false)

        let last = try db.fetchLastLog()
        #expect(last != nil)
        #expect(last?.id == secondId)
        #expect(last?.windowTitle == "Second")
    }

    private func makeTestDB() throws -> DatabaseManager {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("test.db").path
        let db = DatabaseManager(path: dbPath)
        try db.initialize()
        return db
    }
}
