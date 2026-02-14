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

    @Test func createsTag() throws {
        let db = try makeTestDB()
        let tag = try db.createTag(name: "work", colorLight: "#4CAF50", colorDark: "#81C784")
        #expect(tag.id > 0)
        #expect(tag.name == "work")
        #expect(tag.colorLight == "#4CAF50")
        #expect(tag.colorDark == "#81C784")
    }

    @Test func fetchesAllTags() throws {
        let db = try makeTestDB()
        _ = try db.createTag(name: "work", colorLight: "#4CAF50", colorDark: "#81C784")
        _ = try db.createTag(name: "chill", colorLight: "#2196F3", colorDark: "#64B5F6")
        let tags = try db.fetchAllTags()
        #expect(tags.count == 2)
    }

    @Test func updatesTag() throws {
        let db = try makeTestDB()
        let tag = try db.createTag(name: "work", colorLight: "#4CAF50", colorDark: "#81C784")
        try db.updateTag(id: tag.id, name: "working", colorLight: "#FF0000", colorDark: "#CC0000")
        let tags = try db.fetchAllTags()
        #expect(tags.count == 1)
        #expect(tags[0].name == "working")
        #expect(tags[0].colorLight == "#FF0000")
    }

    @Test func deletesTagAndNullifiesReferences() throws {
        let db = try makeTestDB()
        let tag = try db.createTag(name: "work", colorLight: "#4CAF50", colorDark: "#81C784")
        let appId = try db.insertOrGetApp(bundleId: "com.test.app", appName: "TestApp", iconPNG: nil)
        try db.setDefaultTag(appId: appId, tagId: tag.id)
        let now = Date()
        let logId = try db.insertActivityLog(appId: appId, windowTitle: "W", startTime: now, endTime: now, isIdle: false)
        try db.setSessionTag(logId: logId, tagId: tag.id)
        try db.deleteTag(id: tag.id)
        let tags = try db.fetchAllTags()
        #expect(tags.isEmpty)
        let appInfo = try db.fetchAppInfo(appId: appId)
        #expect(appInfo?.defaultTagId == nil)
        let log = try db.fetchLastLog()
        #expect(log?.tagId == nil)
    }

    @Test func rejectsDuplicateTagName() throws {
        let db = try makeTestDB()
        _ = try db.createTag(name: "work", colorLight: "#4CAF50", colorDark: "#81C784")
        #expect(throws: (any Error).self) {
            _ = try db.createTag(name: "work", colorLight: "#FF0000", colorDark: "#CC0000")
        }
    }

    @Test func setsDefaultTagForApp() throws {
        let db = try makeTestDB()
        let tag = try db.createTag(name: "work", colorLight: "#4CAF50", colorDark: "#81C784")
        let appId = try db.insertOrGetApp(bundleId: "com.test.app", appName: "TestApp", iconPNG: nil)
        try db.setDefaultTag(appId: appId, tagId: tag.id)
        let info = try db.fetchAppInfo(appId: appId)
        #expect(info?.defaultTagId == tag.id)
    }

    @Test func setsSessionTag() throws {
        let db = try makeTestDB()
        let tag = try db.createTag(name: "work", colorLight: "#4CAF50", colorDark: "#81C784")
        let appId = try db.insertOrGetApp(bundleId: "com.test.app", appName: "TestApp", iconPNG: nil)
        let now = Date()
        let logId = try db.insertActivityLog(appId: appId, windowTitle: "W", startTime: now, endTime: now, isIdle: false)
        try db.setSessionTag(logId: logId, tagId: tag.id)
        let log = try db.fetchLastLog()
        #expect(log?.tagId == tag.id)
    }

    @Test func clearsSessionTag() throws {
        let db = try makeTestDB()
        let tag = try db.createTag(name: "work", colorLight: "#4CAF50", colorDark: "#81C784")
        let appId = try db.insertOrGetApp(bundleId: "com.test.app", appName: "TestApp", iconPNG: nil)
        let now = Date()
        let logId = try db.insertActivityLog(appId: appId, windowTitle: "W", startTime: now, endTime: now, isIdle: false)
        try db.setSessionTag(logId: logId, tagId: tag.id)
        try db.setSessionTag(logId: logId, tagId: nil)
        let log = try db.fetchLastLog()
        #expect(log?.tagId == nil)
    }

    @Test func fetchesTagSummaries() throws {
        let db = try makeTestDB()
        let workTag = try db.createTag(name: "work", colorLight: "#4CAF50", colorDark: "#81C784")
        let chillTag = try db.createTag(name: "chill", colorLight: "#2196F3", colorDark: "#64B5F6")

        let app1 = try db.insertOrGetApp(bundleId: "com.test.xcode", appName: "Xcode", iconPNG: nil)
        let app2 = try db.insertOrGetApp(bundleId: "com.test.safari", appName: "Safari", iconPNG: nil)

        try db.setDefaultTag(appId: app1, tagId: workTag.id)
        try db.setDefaultTag(appId: app2, tagId: chillTag.id)

        let now = Date()
        _ = try db.insertActivityLog(appId: app1, windowTitle: "W", startTime: now.addingTimeInterval(-100), endTime: now, isIdle: false)
        _ = try db.insertActivityLog(appId: app2, windowTitle: "W", startTime: now.addingTimeInterval(-50), endTime: now, isIdle: false)
        let logId = try db.insertActivityLog(appId: app2, windowTitle: "W2", startTime: now.addingTimeInterval(-200), endTime: now.addingTimeInterval(-170), isIdle: false)
        try db.setSessionTag(logId: logId, tagId: workTag.id)

        let startOfDay = Calendar.current.startOfDay(for: now)
        let summaries = try db.fetchTagSummaries(from: startOfDay, to: now)

        let workSummary = summaries.first { $0.tag?.name == "work" }
        let chillSummary = summaries.first { $0.tag?.name == "chill" }
        #expect(workSummary != nil)
        #expect(chillSummary != nil)
        #expect(Int(workSummary!.totalDuration) == 130)
        #expect(Int(chillSummary!.totalDuration) == 50)
    }

    @Test func fetchesHourlyTagSummaries() throws {
        let db = try makeTestDB()
        let workTag = try db.createTag(name: "work", colorLight: "#4CAF50", colorDark: "#81C784")
        let chillTag = try db.createTag(name: "chill", colorLight: "#2196F3", colorDark: "#64B5F6")

        let app1 = try db.insertOrGetApp(bundleId: "com.test.xcode", appName: "Xcode", iconPNG: nil)
        let app2 = try db.insertOrGetApp(bundleId: "com.test.safari", appName: "Safari", iconPNG: nil)
        try db.setDefaultTag(appId: app1, tagId: workTag.id)

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Hour 9: 30min Xcode (work tag via default), 15min Safari (no tag)
        _ = try db.insertActivityLog(appId: app1, windowTitle: "W", startTime: today.addingTimeInterval(9 * 3600), endTime: today.addingTimeInterval(9 * 3600 + 1800), isIdle: false)
        _ = try db.insertActivityLog(appId: app2, windowTitle: "W", startTime: today.addingTimeInterval(9 * 3600 + 1800), endTime: today.addingTimeInterval(9 * 3600 + 2700), isIdle: false)

        // Hour 10: 20min Safari with session override to chill
        let logId = try db.insertActivityLog(appId: app2, windowTitle: "W", startTime: today.addingTimeInterval(10 * 3600), endTime: today.addingTimeInterval(10 * 3600 + 1200), isIdle: false)
        try db.setSessionTag(logId: logId, tagId: chillTag.id)

        // Hour 9: idle session (should be excluded)
        _ = try db.insertActivityLog(appId: app1, windowTitle: nil, startTime: today.addingTimeInterval(9 * 3600 + 2700), endTime: today.addingTimeInterval(9 * 3600 + 3600), isIdle: true)

        let result = try db.fetchHourlyTagSummaries(for: today)

        // Hour 9 should have work=1800s and untagged=900s
        let hour9 = result[9] ?? []
        let h9work = hour9.first { $0.tagId == workTag.id }
        let h9none = hour9.first { $0.tagId == nil }
        #expect(h9work != nil)
        #expect(Int(h9work!.duration) == 1800)
        #expect(h9none != nil)
        #expect(Int(h9none!.duration) == 900)

        // Hour 10 should have chill=1200s
        let hour10 = result[10] ?? []
        let h10chill = hour10.first { $0.tagId == chillTag.id }
        #expect(h10chill != nil)
        #expect(Int(h10chill!.duration) == 1200)

        // Hour 11 should be empty
        #expect(result[11] == nil || result[11]!.isEmpty)
    }

    @Test func fetchesDailyTagSummaries() throws {
        let db = try makeTestDB()
        let workTag = try db.createTag(name: "work", colorLight: "#4CAF50", colorDark: "#81C784")

        let app1 = try db.insertOrGetApp(bundleId: "com.test.xcode", appName: "Xcode", iconPNG: nil)
        try db.setDefaultTag(appId: app1, tagId: workTag.id)

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = today.addingTimeInterval(-86400)

        // Yesterday: 1 hour of work
        _ = try db.insertActivityLog(appId: app1, windowTitle: "W", startTime: yesterday.addingTimeInterval(9 * 3600), endTime: yesterday.addingTimeInterval(10 * 3600), isIdle: false)

        // Today: 30 min of work
        _ = try db.insertActivityLog(appId: app1, windowTitle: "W", startTime: today.addingTimeInterval(9 * 3600), endTime: today.addingTimeInterval(9 * 3600 + 1800), isIdle: false)

        let weekStart = yesterday.addingTimeInterval(-5 * 86400)
        let weekEnd = today.addingTimeInterval(86400)
        let result = try db.fetchDailyTagSummaries(from: weekStart, to: weekEnd)

        let yesterdayKey = cal.startOfDay(for: yesterday)
        let todayKey = cal.startOfDay(for: today)

        let yesterdaySlots = result[yesterdayKey] ?? []
        let todaySlots = result[todayKey] ?? []

        #expect(yesterdaySlots.count == 1)
        #expect(Int(yesterdaySlots[0].duration) == 3600)
        #expect(todaySlots.count == 1)
        #expect(Int(todaySlots[0].duration) == 1800)
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
