# EmpTracking Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a menubar time-tracking app that automatically monitors the active window every 5 seconds and logs activity to SQLite.

**Architecture:** Menubar-only macOS app (no dock icon). ActivityTracker polls frontmost app + window title via Accessibility API. IdleStateMonitor listens for system events (sleep/lock/screensaver). PowerAssertionChecker prevents false idle detection during video playback. DatabaseManager handles SQLite persistence. TimelineViewController shows logs in a popover.

**Tech Stack:** Swift 5, AppKit (NSStatusItem, NSPopover, NSTableView), Accessibility API, IOKit, SQLite3 (system module), no third-party dependencies.

**Important project notes:**
- Project uses `PBXFileSystemSynchronizedRootGroup` — files created in `EmpTracking/` are auto-discovered by Xcode. No need to edit pbxproj for source files.
- `ENABLE_APP_SANDBOX` must be set to `NO` in pbxproj (currently `YES`).
- Info.plist is auto-generated via build settings (`GENERATE_INFOPLIST_FILE = YES`). Add keys via `INFOPLIST_KEY_*` build settings.
- Swift concurrency: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
- Tests use Swift Testing framework (`import Testing`).
- Build & run: `xcodebuild -project EmpTracking.xcodeproj -scheme EmpTracking build`
- Run tests: `xcodebuild -project EmpTracking.xcodeproj -scheme EmpTracking test`

---

### Task 1: Configure project settings

Disable App Sandbox, add LSUIElement, add Accessibility usage description.

**Files:**
- Modify: `EmpTracking.xcodeproj/project.pbxproj`

**Step 1: Disable App Sandbox**

In `project.pbxproj`, find both Debug and Release build configurations for the EmpTracking target (IDs `9544A6B92F3CDFC900241B21` and `9544A6BA2F3CDFC900241B21`). In each, change:

```
ENABLE_APP_SANDBOX = YES;
```
to:
```
ENABLE_APP_SANDBOX = NO;
```

**Step 2: Add Info.plist keys via build settings**

In the same two build configurations, add these keys inside `buildSettings`:

```
INFOPLIST_KEY_LSUIElement = YES;
INFOPLIST_KEY_NSAccessibilityUsageDescription = "EmpTracking needs Accessibility access to read window titles for time tracking.";
```

**Step 3: Verify build**

Run: `xcodebuild -project EmpTracking.xcodeproj -scheme EmpTracking build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add EmpTracking.xcodeproj/project.pbxproj
git commit -m "configure: disable sandbox, add LSUIElement and accessibility description"
```

---

### Task 2: Create data models

**Files:**
- Create: `EmpTracking/Models/AppInfo.swift`
- Create: `EmpTracking/Models/ActivityLog.swift`

**Step 1: Create AppInfo model**

Create `EmpTracking/Models/AppInfo.swift`:

```swift
import Cocoa

struct AppInfo {
    let id: Int64
    let bundleId: String
    let appName: String
    let icon: NSImage?
}
```

**Step 2: Create ActivityLog model**

Create `EmpTracking/Models/ActivityLog.swift`:

```swift
import Foundation

struct ActivityLog {
    let id: Int64
    let appId: Int64
    let windowTitle: String?
    let startTime: Date
    var endTime: Date
    let isIdle: Bool
}
```

**Step 3: Verify build**

Run: `xcodebuild -project EmpTracking.xcodeproj -scheme EmpTracking build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add EmpTracking/Models/
git commit -m "add AppInfo and ActivityLog data models"
```

---

### Task 3: Implement DatabaseManager

**Files:**
- Create: `EmpTracking/Services/DatabaseManager.swift`
- Modify: `EmpTrackingTests/EmpTrackingTests.swift`

**Step 1: Write failing tests for DatabaseManager**

Replace contents of `EmpTrackingTests/EmpTrackingTests.swift`:

```swift
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
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild -project EmpTracking.xcodeproj -scheme EmpTracking test 2>&1 | grep -E "(Test|error|FAILED|SUCCEEDED)" | tail -20`
Expected: Compilation errors — `DatabaseManager` does not exist yet.

**Step 3: Implement DatabaseManager**

Create `EmpTracking/Services/DatabaseManager.swift`:

```swift
import Foundation
import SQLite3

final class DatabaseManager: @unchecked Sendable {
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
        // Try to find existing
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

        // Insert new
        let insert = "INSERT INTO apps (bundle_id, app_name, icon) VALUES (?, ?, ?)"
        if sqlite3_prepare_v2(db, insert, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (bundleId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (appName as NSString).utf8String, -1, nil)
            if let iconData = iconPNG {
                iconData.withUnsafeBytes { rawBuffer in
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
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild -project EmpTracking.xcodeproj -scheme EmpTracking test 2>&1 | grep -E "(Test|PASSED|FAILED|SUCCEEDED)" | tail -20`
Expected: All tests pass.

**Step 5: Commit**

```bash
git add EmpTracking/Services/DatabaseManager.swift EmpTrackingTests/EmpTrackingTests.swift
git commit -m "implement DatabaseManager with SQLite CRUD and tests"
```

---

### Task 4: Implement PowerAssertionChecker

**Files:**
- Create: `EmpTracking/Services/PowerAssertionChecker.swift`

**Step 1: Implement PowerAssertionChecker**

Create `EmpTracking/Services/PowerAssertionChecker.swift`:

```swift
import IOKit

enum PowerAssertionChecker {

    private static let mediaAssertionTypes: Set<String> = [
        "PreventUserIdleDisplaySleep",
        "PreventUserIdleSystemSleep"
    ]

    static func processHasMediaAssertion(pid: pid_t) -> Bool {
        var assertionsByProcess: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&assertionsByProcess)

        guard result == kIOReturnSuccess,
              let cfDict = assertionsByProcess?.takeRetainedValue() as NSDictionary? else {
            return false
        }

        let pidKey = NSNumber(value: pid)
        guard let assertions = cfDict[pidKey] as? [[String: Any]] else {
            return false
        }

        return assertions.contains { assertion in
            guard let type = assertion[kIOPMAssertionTypeKey] as? String,
                  let level = (assertion[kIOPMAssertionLevelKey] as? NSNumber)?.intValue else {
                return false
            }
            return level > 0 && mediaAssertionTypes.contains(type)
        }
    }
}
```

**Step 2: Verify build**

Run: `xcodebuild -project EmpTracking.xcodeproj -scheme EmpTracking build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add EmpTracking/Services/PowerAssertionChecker.swift
git commit -m "add PowerAssertionChecker for media playback detection"
```

---

### Task 5: Implement IdleStateMonitor

**Files:**
- Create: `EmpTracking/Services/IdleStateMonitor.swift`

**Step 1: Implement IdleStateMonitor**

Create `EmpTracking/Services/IdleStateMonitor.swift`:

```swift
import Cocoa
import CoreGraphics

final class IdleStateMonitor {
    private(set) var isUserAway = false
    private var observers: [Any] = []

    var onAwayStateChanged: ((Bool) -> Void)?

    private static let idleThreshold: TimeInterval = 120 // 2 minutes

    func start() {
        let wsnc = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()

        // Sleep / Wake
        observers.append(wsnc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in self?.setAway(true) })

        observers.append(wsnc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.setAway(false) })

        // Display off / on
        observers.append(wsnc.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main) { [weak self] _ in self?.setAway(true) })

        observers.append(wsnc.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.setAway(false) })

        // Fast user switching
        observers.append(wsnc.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in self?.setAway(true) })

        observers.append(wsnc.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in self?.setAway(false) })

        // Screen lock / unlock
        observers.append(dnc.addObserver(
            forName: .init("com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] _ in self?.setAway(true) })

        observers.append(dnc.addObserver(
            forName: .init("com.apple.screenIsUnlocked"),
            object: nil, queue: .main) { [weak self] _ in self?.setAway(false) })

        // Screen saver
        observers.append(dnc.addObserver(
            forName: .init("com.apple.screensaver.didstart"),
            object: nil, queue: .main) { [weak self] _ in self?.setAway(true) })

        observers.append(dnc.addObserver(
            forName: .init("com.apple.screensaver.didstop"),
            object: nil, queue: .main) { [weak self] _ in self?.setAway(false) })
    }

    func stop() {
        let wsnc = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()
        for observer in observers {
            wsnc.removeObserver(observer)
            dnc.removeObserver(observer)
        }
        observers.removeAll()
    }

    func isUserIdle() -> Bool {
        let idleTime = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: CGEventType(rawValue: ~0)!
        )
        guard idleTime >= Self.idleThreshold else { return false }

        // Check if frontmost app is playing media
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            if PowerAssertionChecker.processHasMediaAssertion(pid: frontApp.processIdentifier) {
                return false
            }
        }

        return true
    }

    private func setAway(_ away: Bool) {
        guard isUserAway != away else { return }
        isUserAway = away
        onAwayStateChanged?(away)
    }
}
```

**Step 2: Verify build**

Run: `xcodebuild -project EmpTracking.xcodeproj -scheme EmpTracking build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add EmpTracking/Services/IdleStateMonitor.swift
git commit -m "add IdleStateMonitor for system events and idle detection"
```

---

### Task 6: Implement ActivityTracker

**Files:**
- Create: `EmpTracking/Services/ActivityTracker.swift`

**Step 1: Implement ActivityTracker**

Create `EmpTracking/Services/ActivityTracker.swift`:

```swift
import Cocoa
import ApplicationServices

final class ActivityTracker {
    private let db: DatabaseManager
    private let idleMonitor: IdleStateMonitor
    private var timer: Timer?
    private var currentLogId: Int64?
    private var currentBundleId: String?
    private var currentWindowTitle: String?
    private var isCurrentlyIdle = false

    var onUpdate: (() -> Void)?

    init(db: DatabaseManager, idleMonitor: IdleStateMonitor) {
        self.db = db
        self.idleMonitor = idleMonitor

        idleMonitor.onAwayStateChanged = { [weak self] away in
            if away {
                self?.finalizeCurrentLog()
            }
        }
    }

    func start() {
        requestAccessibilityIfNeeded()
        idleMonitor.start()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        idleMonitor.stop()
    }

    private func tick() {
        guard !idleMonitor.isUserAway else { return }

        let isIdle = idleMonitor.isUserIdle()

        if isIdle {
            if !isCurrentlyIdle {
                // Transition to idle
                finalizeCurrentLog()
                isCurrentlyIdle = true
                startNewLog(appName: "Idle", bundleId: "com.emptracking.idle", windowTitle: nil, isIdle: true, icon: nil)
            } else {
                updateCurrentLogEndTime()
            }
            return
        }

        // User is active
        if isCurrentlyIdle {
            finalizeCurrentLog()
            isCurrentlyIdle = false
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier,
              let appName = frontApp.localizedName else { return }

        let windowTitle = getWindowTitle(for: frontApp)

        if bundleId == currentBundleId && windowTitle == currentWindowTitle {
            updateCurrentLogEndTime()
        } else {
            finalizeCurrentLog()
            let iconData = frontApp.icon.flatMap { iconToData($0) }
            startNewLog(appName: appName, bundleId: bundleId, windowTitle: windowTitle, isIdle: false, icon: iconData)
        }
    }

    private func startNewLog(appName: String, bundleId: String, windowTitle: String?, isIdle: Bool, icon: Data?) {
        do {
            let appId = try db.insertOrGetApp(bundleId: bundleId, appName: appName, iconPNG: icon)
            let now = Date()
            let logId = try db.insertActivityLog(appId: appId, windowTitle: windowTitle, startTime: now, endTime: now, isIdle: isIdle)
            currentLogId = logId
            currentBundleId = bundleId
            currentWindowTitle = windowTitle
            onUpdate?()
        } catch {
            print("Error starting log: \(error)")
        }
    }

    private func updateCurrentLogEndTime() {
        guard let logId = currentLogId else { return }
        do {
            try db.updateEndTime(logId: logId, endTime: Date())
        } catch {
            print("Error updating log: \(error)")
        }
    }

    private func finalizeCurrentLog() {
        updateCurrentLogEndTime()
        currentLogId = nil
        currentBundleId = nil
        currentWindowTitle = nil
    }

    private func getWindowTitle(for app: NSRunningApplication) -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: AnyObject?
        let windowResult = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &windowValue
        )
        guard windowResult == .success else { return nil }

        var titleValue: AnyObject?
        let titleResult = AXUIElementCopyAttributeValue(
            windowValue as! AXUIElement, kAXTitleAttribute as CFString, &titleValue
        )
        guard titleResult == .success else { return nil }

        return titleValue as? String
    }

    private func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func iconToData(_ icon: NSImage) -> Data? {
        let size = NSSize(width: 32, height: 32)
        let resized = NSImage(size: size)
        resized.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: size))
        resized.unlockFocus()

        guard let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData
    }
}
```

**Step 2: Verify build**

Run: `xcodebuild -project EmpTracking.xcodeproj -scheme EmpTracking build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add EmpTracking/Services/ActivityTracker.swift
git commit -m "implement ActivityTracker with idle-aware activity logging"
```

---

### Task 7: Implement TimelineViewController

**Files:**
- Create: `EmpTracking/Views/TimelineViewController.swift`
- Create: `EmpTracking/Views/TimelineCellView.swift`

**Step 1: Create TimelineCellView**

Create `EmpTracking/Views/TimelineCellView.swift`:

```swift
import Cocoa

final class TimelineCellView: NSTableCellView {
    let iconView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let timeLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = .secondaryLabelColor
        addSubview(timeLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),

            timeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            timeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
        ])
    }

    func configure(appName: String, windowTitle: String?, startTime: Date, endTime: Date, icon: NSImage?, isIdle: Bool) {
        let title: String
        if isIdle {
            title = "Idle"
            titleLabel.textColor = .tertiaryLabelColor
        } else if let windowTitle = windowTitle, !windowTitle.isEmpty {
            title = "\(appName) — \(windowTitle)"
            titleLabel.textColor = .labelColor
        } else {
            title = appName
            titleLabel.textColor = .labelColor
        }
        titleLabel.stringValue = title

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let duration = Int(endTime.timeIntervalSince(startTime))
        let durationText: String
        if duration < 60 {
            durationText = "\(duration) сек"
        } else {
            durationText = "\(duration / 60) мин"
        }
        timeLabel.stringValue = "\(formatter.string(from: startTime)) – \(formatter.string(from: endTime))  (\(durationText))"

        if isIdle {
            iconView.image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "Idle")
        } else {
            iconView.image = icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: "App")
        }
    }
}
```

**Step 2: Create TimelineViewController**

Create `EmpTracking/Views/TimelineViewController.swift`:

```swift
import Cocoa

final class TimelineViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let db: DatabaseManager
    private var logs: [ActivityLog] = []
    private var appCache: [Int64: AppInfo] = [:]

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let headerLabel = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "")

    init(db: DatabaseManager) {
        self.db = db
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        self.view = container

        // Header
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        container.addSubview(headerLabel)

        totalLabel.translatesAutoresizingMaskIntoConstraints = false
        totalLabel.font = .systemFont(ofSize: 12)
        totalLabel.textColor = .secondaryLabelColor
        container.addSubview(totalLabel)

        // Table
        let column = NSTableColumn(identifier: .init("activity"))
        column.title = ""
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 48
        tableView.style = .plain

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        container.addSubview(scrollView)

        // Quit button
        let quitButton = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        quitButton.bezelStyle = .inline
        quitButton.font = .systemFont(ofSize: 11)
        container.addSubview(quitButton)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            headerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),

            totalLabel.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
            totalLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: quitButton.topAnchor, constant: -8),

            quitButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            quitButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
    }

    func reload() {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        formatter.locale = Locale(identifier: "ru_RU")
        headerLabel.stringValue = formatter.string(from: Date())

        do {
            logs = try db.fetchTodayLogs()

            let totalActive = logs.filter { !$0.isIdle }
                .reduce(0.0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
            let hours = Int(totalActive) / 3600
            let minutes = (Int(totalActive) % 3600) / 60
            totalLabel.stringValue = "Активно: \(hours)ч \(minutes)мин"

            // Load app info
            let appIds = Set(logs.map { $0.appId })
            for appId in appIds where appCache[appId] == nil {
                appCache[appId] = try db.fetchAppInfo(appId: appId)
            }
        } catch {
            print("Error fetching logs: \(error)")
        }

        tableView.reloadData()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        logs.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("TimelineCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? TimelineCellView)
            ?? TimelineCellView()
        cell.identifier = id

        let log = logs[row]
        let appInfo = appCache[log.appId]

        cell.configure(
            appName: appInfo?.appName ?? "Unknown",
            windowTitle: log.windowTitle,
            startTime: log.startTime,
            endTime: log.endTime,
            icon: appInfo?.icon,
            isIdle: log.isIdle
        )

        return cell
    }
}
```

**Step 2: Verify build**

Run: `xcodebuild -project EmpTracking.xcodeproj -scheme EmpTracking build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add EmpTracking/Views/
git commit -m "add TimelineViewController and TimelineCellView for activity log display"
```

---

### Task 8: Wire up AppDelegate with menubar

**Files:**
- Modify: `EmpTracking/AppDelegate.swift`
- Delete scene from storyboard or remove storyboard reference (will handle programmatically)

**Step 1: Rewrite AppDelegate**

Replace contents of `EmpTracking/AppDelegate.swift`:

```swift
import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var db: DatabaseManager!
    private var tracker: ActivityTracker!
    private var timelineVC: TimelineViewController!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Close the default window from storyboard if present
        NSApp.windows.forEach { $0.close() }

        setupDatabase()
        setupMenubar()
        setupTracker()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        tracker?.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    private func setupDatabase() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("EmpTracking")
        let dbPath = dbDir.appendingPathComponent("tracking.db").path

        db = DatabaseManager(path: dbPath)
        do {
            try db.initialize()
        } catch {
            print("Failed to initialize database: \(error)")
        }
    }

    private func setupMenubar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "EmpTracking")
            button.action = #selector(togglePopover)
        }

        timelineVC = TimelineViewController(db: db)

        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 500)
        popover.behavior = .transient
        popover.contentViewController = timelineVC
    }

    private func setupTracker() {
        let idleMonitor = IdleStateMonitor()
        tracker = ActivityTracker(db: db, idleMonitor: idleMonitor)
        tracker.onUpdate = { [weak self] in
            if self?.popover.isShown == true {
                self?.timelineVC.reload()
            }
        }
        tracker.start()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            timelineVC.reload()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
```

**Step 2: Remove the window controller and view controller scenes from the storyboard**

The storyboard still has the window controller and view controller scenes. We need to keep the Application scene (with the menu) but remove the window. Update `Main.storyboard` to remove the Window Controller and View Controller scenes, and remove `initialViewController="B8D-0N-5wS"` from the document tag.

Alternatively, the simplest approach: remove `INFOPLIST_KEY_NSMainStoryboardFile = Main;` from build settings (in both Debug and Release configs in pbxproj). This prevents the storyboard from auto-loading the window. The menu will be created from the storyboard Application scene, but no window will appear.

Actually, the cleanest approach for a menubar-only app: remove the storyboard reference from build settings. The app menu won't load from storyboard, but for a menubar app we don't need the standard menu bar either — the popover is our UI.

In `project.pbxproj`, remove this line from both Debug (`9544A6B92F3CDFC900241B21`) and Release (`9544A6BA2F3CDFC900241B21`) build configs:

```
INFOPLIST_KEY_NSMainStoryboardFile = Main;
```

**Step 3: Verify build**

Run: `xcodebuild -project EmpTracking.xcodeproj -scheme EmpTracking build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add EmpTracking/AppDelegate.swift EmpTracking.xcodeproj/project.pbxproj
git commit -m "wire up AppDelegate with menubar, popover, and activity tracker"
```

---

### Task 9: Manual smoke test

This task cannot be automated — it requires running the app and verifying visually.

**Step 1: Build and run**

Run: `xcodebuild -project EmpTracking.xcodeproj -scheme EmpTracking build 2>&1 | tail -5`

Then launch the built app manually or via Xcode.

**Step 2: Verify checklist**

- [ ] Clock icon appears in the menubar
- [ ] No dock icon visible
- [ ] Click menubar icon opens popover with today's date
- [ ] System prompts for Accessibility permission
- [ ] After granting permission, activity logs appear with app name + window title
- [ ] Switching apps creates new log entries
- [ ] After 2 minutes of no input (and no video playing), an Idle entry appears
- [ ] Locking screen pauses tracking, unlocking resumes it

**Step 3: Final commit with any fixes**

```bash
git add -A
git commit -m "finalize EmpTracking v1.0 menubar time tracker"
```
