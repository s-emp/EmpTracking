# Tag System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a tagging system where apps have default tags, sessions can override tags, and the UI supports grouping by tags.

**Architecture:** New `tags` table with FK references from `apps.default_tag_id` and `activity_logs.tag_id`. Migration via ALTER TABLE for existing databases. UI changes in TimelineView (replace period segment with Apps/Tags) and DetailView (add Apps/Tags segment + click-to-tag sessions).

**Tech Stack:** Swift 5, AppKit, SQLite3 (raw C API), Swift Testing framework

---

### Task 1: Add Tag model

**Files:**
- Create: `EmpTracking/Models/Tag.swift`
- Create: `EmpTracking/Models/TagSummary.swift`

**Step 1: Create Tag model**

```swift
// EmpTracking/Models/Tag.swift
import Foundation

struct Tag {
    let id: Int64
    let name: String
    let colorLight: String
    let colorDark: String
}
```

**Step 2: Create TagSummary model**

```swift
// EmpTracking/Models/TagSummary.swift
import Foundation

struct TagSummary {
    let tag: Tag?
    let totalDuration: TimeInterval
}
```

**Step 3: Commit**

```bash
git add EmpTracking/Models/Tag.swift EmpTracking/Models/TagSummary.swift
git commit -m "add Tag and TagSummary models"
```

---

### Task 2: Database migration — tags table and new columns

**Files:**
- Modify: `EmpTracking/Services/DatabaseManager.swift:17-44` (the `initialize()` method)

**Step 1: Write failing test for migration**

Add to `EmpTrackingTests/EmpTrackingTests.swift`:

```swift
@Test func createsTagsTableOnInitialize() throws {
    let db = try makeTestDB()

    // Verify tags table exists by inserting a tag
    let tag = try db.createTag(name: "work", colorLight: "#4CAF50", colorDark: "#81C784")
    #expect(tag.id > 0)
    #expect(tag.name == "work")
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project EmpTracking.xcodeproj -scheme EmpTracking -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — `createTag` method does not exist

**Step 3: Add migration to DatabaseManager.initialize()**

In `DatabaseManager.swift`, after the existing `CREATE TABLE IF NOT EXISTS activity_logs` block (line 43), add:

```swift
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
```

Add private helper method at the bottom of the class (before the closing `}`):

```swift
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
```

**Step 4: Proceed to Task 3 (createTag needed for test to pass)**

Note: The test from Step 1 depends on `createTag`, which is implemented in Task 3. This test will pass after Task 3.

**Step 5: Commit migration only**

```bash
git add EmpTracking/Services/DatabaseManager.swift
git commit -m "add tags table and migration columns to apps and activity_logs"
```

---

### Task 3: Tag CRUD methods + tests

**Files:**
- Modify: `EmpTracking/Services/DatabaseManager.swift`
- Modify: `EmpTrackingTests/EmpTrackingTests.swift`

**Step 1: Write failing tests for all tag CRUD operations**

Add to `EmpTrackingTests/EmpTrackingTests.swift`:

```swift
@Test func createsTagsTableOnInitialize() throws {
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
}

@Test func rejectsDuplicateTagName() throws {
    let db = try makeTestDB()
    _ = try db.createTag(name: "work", colorLight: "#4CAF50", colorDark: "#81C784")
    #expect(throws: (any Error).self) {
        _ = try db.createTag(name: "work", colorLight: "#FF0000", colorDark: "#CC0000")
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project EmpTracking.xcodeproj -scheme EmpTracking -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — methods do not exist

**Step 3: Implement CRUD methods in DatabaseManager**

Add to `DatabaseManager.swift` (before `private func logFromStatement`):

```swift
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
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project EmpTracking.xcodeproj -scheme EmpTracking -destination 'platform=macOS' 2>&1 | tail -20`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add EmpTracking/Services/DatabaseManager.swift EmpTrackingTests/EmpTrackingTests.swift
git commit -m "add tag CRUD methods with tests"
```

---

### Task 4: setDefaultTag, setSessionTag + tests

**Files:**
- Modify: `EmpTracking/Services/DatabaseManager.swift`
- Modify: `EmpTrackingTests/EmpTrackingTests.swift`

**Step 1: Write failing tests**

Add to `EmpTrackingTests/EmpTrackingTests.swift`:

```swift
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
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project EmpTracking.xcodeproj -scheme EmpTracking -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — methods/properties do not exist

**Step 3: Add setDefaultTag and setSessionTag to DatabaseManager**

Add to `DatabaseManager.swift` (in the Tag CRUD section):

```swift
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
```

**Step 4: Update AppInfo model to include defaultTagId**

Modify `EmpTracking/Models/AppInfo.swift`:

```swift
import Cocoa

struct AppInfo {
    let id: Int64
    let bundleId: String
    let appName: String
    let icon: NSImage?
    let defaultTagId: Int64?
}
```

**Step 5: Update ActivityLog model to include tagId**

Modify `EmpTracking/Models/ActivityLog.swift`:

```swift
import Foundation

struct ActivityLog {
    let id: Int64
    let appId: Int64
    let windowTitle: String?
    let startTime: Date
    var endTime: Date
    let isIdle: Bool
    let tagId: Int64?
}
```

**Step 6: Update DatabaseManager to read new fields**

Update `fetchAppInfo` (line 203-233) — add `default_tag_id` to the SELECT and to the AppInfo constructor:

```swift
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
```

Update `logFromStatement` (line 235-245) — add `tag_id`:

```swift
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
```

Update all SQL queries that use `logFromStatement` to include `tag_id` in the SELECT:

- `fetchLastLog` (line 124): change to `SELECT id, app_id, window_title, start_time, end_time, is_idle, tag_id FROM activity_logs ORDER BY id DESC LIMIT 1`
- `fetchTodayLogs` (line 143): change to `SELECT id, app_id, window_title, start_time, end_time, is_idle, tag_id FROM activity_logs WHERE start_time >= ? ORDER BY start_time DESC`

**Step 7: Run tests to verify they pass**

Run: `xcodebuild test -project EmpTracking.xcodeproj -scheme EmpTracking -destination 'platform=macOS' 2>&1 | tail -20`
Expected: ALL PASS

**Step 8: Commit**

```bash
git add EmpTracking/Models/AppInfo.swift EmpTracking/Models/ActivityLog.swift EmpTracking/Services/DatabaseManager.swift EmpTrackingTests/EmpTrackingTests.swift
git commit -m "add setDefaultTag, setSessionTag and tag fields on models"
```

---

### Task 5: fetchTagSummaries + test

**Files:**
- Modify: `EmpTracking/Services/DatabaseManager.swift`
- Modify: `EmpTrackingTests/EmpTrackingTests.swift`

**Step 1: Write failing test**

Add to `EmpTrackingTests/EmpTrackingTests.swift`:

```swift
@Test func fetchesTagSummaries() throws {
    let db = try makeTestDB()
    let workTag = try db.createTag(name: "work", colorLight: "#4CAF50", colorDark: "#81C784")
    let chillTag = try db.createTag(name: "chill", colorLight: "#2196F3", colorDark: "#64B5F6")

    let app1 = try db.insertOrGetApp(bundleId: "com.test.xcode", appName: "Xcode", iconPNG: nil)
    let app2 = try db.insertOrGetApp(bundleId: "com.test.safari", appName: "Safari", iconPNG: nil)

    try db.setDefaultTag(appId: app1, tagId: workTag.id)
    try db.setDefaultTag(appId: app2, tagId: chillTag.id)

    let now = Date()
    // Xcode session: 100 seconds, tag from app default (work)
    _ = try db.insertActivityLog(appId: app1, windowTitle: "W", startTime: now.addingTimeInterval(-100), endTime: now, isIdle: false)
    // Safari session: 50 seconds, tag from app default (chill)
    _ = try db.insertActivityLog(appId: app2, windowTitle: "W", startTime: now.addingTimeInterval(-50), endTime: now, isIdle: false)
    // Safari session with override: 30 seconds, explicitly tagged as work
    let logId = try db.insertActivityLog(appId: app2, windowTitle: "W2", startTime: now.addingTimeInterval(-200), endTime: now.addingTimeInterval(-170), isIdle: false)
    try db.setSessionTag(logId: logId, tagId: workTag.id)

    let startOfDay = Calendar.current.startOfDay(for: now)
    let summaries = try db.fetchTagSummaries(from: startOfDay, to: now)

    // work: 100 (xcode) + 30 (safari override) = 130
    // chill: 50 (safari)
    let workSummary = summaries.first { $0.tag?.name == "work" }
    let chillSummary = summaries.first { $0.tag?.name == "chill" }
    #expect(workSummary != nil)
    #expect(chillSummary != nil)
    #expect(Int(workSummary!.totalDuration) == 130)
    #expect(Int(chillSummary!.totalDuration) == 50)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project EmpTracking.xcodeproj -scheme EmpTracking -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — `fetchTagSummaries` does not exist

**Step 3: Implement fetchTagSummaries**

Add to `DatabaseManager.swift` (in the Tag section):

```swift
func fetchTagSummaries(from: Date, to: Date) throws -> [TagSummary] {
    // Resolve tag: session tag_id overrides app default_tag_id
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
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project EmpTracking.xcodeproj -scheme EmpTracking -destination 'platform=macOS' 2>&1 | tail -20`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add EmpTracking/Services/DatabaseManager.swift EmpTrackingTests/EmpTrackingTests.swift
git commit -m "add fetchTagSummaries with resolved tag logic"
```

---

### Task 6: TimelineView — replace segment with Apps/Tags and add tag summary mode

**Files:**
- Modify: `EmpTracking/Views/TimelineViewController.swift`
- Create: `EmpTracking/Views/TagCellView.swift`

**Step 1: Create TagCellView**

```swift
// EmpTracking/Views/TagCellView.swift
import Cocoa

final class TagCellView: NSTableCellView {
    private let colorDot = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        colorDot.translatesAutoresizingMaskIntoConstraints = false
        colorDot.wantsLayer = true
        colorDot.layer?.cornerRadius = 6
        addSubview(colorDot)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .systemFont(ofSize: 13)
        durationLabel.textColor = .secondaryLabelColor
        durationLabel.alignment = .right
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(durationLabel)

        NSLayoutConstraint.activate([
            colorDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            colorDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            colorDot.widthAnchor.constraint(equalToConstant: 12),
            colorDot.heightAnchor.constraint(equalToConstant: 12),

            titleLabel.leadingAnchor.constraint(equalTo: colorDot.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor, constant: -8),

            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            durationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(summary: TagSummary) {
        if let tag = summary.tag {
            titleLabel.stringValue = tag.name
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? tag.colorDark : tag.colorLight
            colorDot.layer?.backgroundColor = NSColor(hex: hex).cgColor
        } else {
            titleLabel.stringValue = "Без тега"
            colorDot.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
        }

        let total = Int(summary.totalDuration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            durationLabel.stringValue = "\(hours)ч \(minutes)мин"
        } else {
            durationLabel.stringValue = "\(minutes)мин"
        }
    }
}
```

**Step 2: Add NSColor hex initializer**

Create `EmpTracking/Extensions/NSColor+Hex.swift`:

```swift
import Cocoa

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)

        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
```

**Step 3: Rewrite TimelineViewController**

Replace the full content of `EmpTracking/Views/TimelineViewController.swift`:

```swift
import Cocoa

final class TimelineViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let db: DatabaseManager
    private var appSummaries: [AppSummary] = []
    private var tagSummaries: [TagSummary] = []
    var onDetail: (() -> Void)?

    private enum Mode: Int { case apps = 0, tags = 1 }
    private var mode: Mode = .apps

    private let segmentedControl = NSSegmentedControl()
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

        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        container.addSubview(headerLabel)

        totalLabel.translatesAutoresizingMaskIntoConstraints = false
        totalLabel.font = .systemFont(ofSize: 12)
        totalLabel.textColor = .secondaryLabelColor
        container.addSubview(totalLabel)

        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.segmentCount = 2
        segmentedControl.setLabel("Приложения", forSegment: 0)
        segmentedControl.setLabel("Теги", forSegment: 1)
        segmentedControl.selectedSegment = 0
        segmentedControl.target = self
        segmentedControl.action = #selector(segmentChanged(_:))
        segmentedControl.segmentStyle = .rounded
        container.addSubview(segmentedControl)

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
        scrollView.drawsBackground = false
        tableView.backgroundColor = .clear
        container.addSubview(scrollView)

        let detailButton = NSButton(title: "Подробнее", target: self, action: #selector(detailTapped))
        detailButton.translatesAutoresizingMaskIntoConstraints = false
        detailButton.bezelStyle = .inline
        detailButton.font = .systemFont(ofSize: 11)
        container.addSubview(detailButton)

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

            segmentedControl.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            segmentedControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: quitButton.topAnchor, constant: -8),

            detailButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            detailButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),

            quitButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            quitButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        mode = Mode(rawValue: sender.selectedSegment) ?? .apps
        reload()
    }

    @objc private func detailTapped() {
        onDetail?()
    }

    func reload() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        headerLabel.stringValue = formatter.string(from: Date())

        let since = Calendar.current.startOfDay(for: Date())

        do {
            switch mode {
            case .apps:
                appSummaries = try db.fetchAppSummaries(since: since)
                let total = appSummaries.reduce(0.0) { $0 + $1.totalDuration }
                totalLabel.stringValue = formatDuration(total)

            case .tags:
                tagSummaries = try db.fetchTagSummaries(from: since, to: Date())
                let total = tagSummaries.reduce(0.0) { $0 + $1.totalDuration }
                totalLabel.stringValue = formatDuration(total)
            }
        } catch {
            print("Error fetching summaries: \(error)")
        }

        tableView.reloadData()
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)ч \(minutes)мин"
    }

    // MARK: - NSTableViewDataSource

    nonisolated func numberOfRows(in tableView: NSTableView) -> Int {
        MainActor.assumeIsolated {
            switch mode {
            case .apps: return appSummaries.count
            case .tags: return tagSummaries.count
            }
        }
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch mode {
        case .apps:
            let id = NSUserInterfaceItemIdentifier("TimelineCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? TimelineCellView)
                ?? TimelineCellView()
            cell.identifier = id
            cell.configure(summary: appSummaries[row])
            return cell

        case .tags:
            let id = NSUserInterfaceItemIdentifier("TagCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? TagCellView)
                ?? TagCellView()
            cell.identifier = id
            cell.configure(summary: tagSummaries[row])
            return cell
        }
    }
}
```

**Step 4: Commit**

```bash
git add EmpTracking/Views/TimelineViewController.swift EmpTracking/Views/TagCellView.swift EmpTracking/Extensions/NSColor+Hex.swift
git commit -m "replace period segment with Apps/Tags mode in timeline"
```

---

### Task 7: Tag assignment menu in TimelineView (apps mode)

**Files:**
- Modify: `EmpTracking/Views/TimelineViewController.swift`

**Step 1: Add click handler for table rows in apps mode**

Add `NSTableViewDelegate` method and tag menu builder to `TimelineViewController`:

```swift
func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    guard mode == .apps else { return false }
    let summary = appSummaries[row]
    showTagMenu(forAppId: summary.appId, at: row)
    return false
}

private func showTagMenu(forAppId appId: Int64, at row: Int) {
    let menu = NSMenu()

    let tags: [Tag]
    let appInfo: AppInfo?
    do {
        tags = try db.fetchAllTags()
        appInfo = try db.fetchAppInfo(appId: appId)
    } catch {
        print("Error loading tags: \(error)")
        return
    }

    let currentTagId = appInfo?.defaultTagId

    // "No tag" item
    let noTagItem = NSMenuItem(title: "Без тега", action: #selector(tagMenuItemClicked(_:)), keyEquivalent: "")
    noTagItem.target = self
    noTagItem.representedObject = TagMenuAction(appId: appId, tagId: nil)
    if currentTagId == nil { noTagItem.state = .on }
    menu.addItem(noTagItem)

    if !tags.isEmpty {
        menu.addItem(.separator())
    }

    // Tag items
    for tag in tags {
        let item = NSMenuItem(title: tag.name, action: #selector(tagMenuItemClicked(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = TagMenuAction(appId: appId, tagId: tag.id)
        if currentTagId == tag.id { item.state = .on }

        // Color dot as attributed title
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = NSColor(hex: isDark ? tag.colorDark : tag.colorLight)
        let dot = NSAttributedString(string: "● ", attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 13)])
        let name = NSAttributedString(string: tag.name, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        let title = NSMutableAttributedString()
        title.append(dot)
        title.append(name)
        item.attributedTitle = title

        menu.addItem(item)
    }

    menu.addItem(.separator())

    // "Create tag..." item
    let createItem = NSMenuItem(title: "Создать тег...", action: #selector(createTagClicked(_:)), keyEquivalent: "")
    createItem.target = self
    menu.addItem(createItem)

    let rect = tableView.rect(ofRow: row)
    menu.popUp(positioning: nil, at: NSPoint(x: rect.midX, y: rect.midY), in: tableView)
}

@objc private func tagMenuItemClicked(_ sender: NSMenuItem) {
    guard let action = sender.representedObject as? TagMenuAction else { return }
    do {
        try db.setDefaultTag(appId: action.appId, tagId: action.tagId)
        reload()
    } catch {
        print("Error setting tag: \(error)")
    }
}
```

**Step 2: Add TagMenuAction helper struct**

Add at the top of the file (outside the class) or as a nested type:

```swift
private struct TagMenuAction {
    let appId: Int64
    let tagId: Int64?
}
```

**Step 3: Add createTagClicked and inline tag creation form**

```swift
@objc private func createTagClicked(_ sender: NSMenuItem) {
    showCreateTagForm()
}

private func showCreateTagForm() {
    let alert = NSAlert()
    alert.messageText = "Создать тег"
    alert.addButton(withTitle: "Создать")
    alert.addButton(withTitle: "Отмена")

    let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))

    let nameField = NSTextField(frame: NSRect(x: 0, y: 70, width: 300, height: 24))
    nameField.placeholderString = "Название тега"
    container.addSubview(nameField)

    let lightLabel = NSTextField(labelWithString: "Светлая:")
    lightLabel.frame = NSRect(x: 0, y: 35, width: 60, height: 20)
    container.addSubview(lightLabel)

    let lightColorWell = NSColorWell(frame: NSRect(x: 65, y: 30, width: 50, height: 30))
    lightColorWell.color = .systemGreen
    container.addSubview(lightColorWell)

    let darkLabel = NSTextField(labelWithString: "Тёмная:")
    darkLabel.frame = NSRect(x: 150, y: 35, width: 60, height: 20)
    container.addSubview(darkLabel)

    let darkColorWell = NSColorWell(frame: NSRect(x: 215, y: 30, width: 50, height: 30))
    darkColorWell.color = .systemGreen
    container.addSubview(darkColorWell)

    alert.accessoryView = container

    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else { return }

    let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }

    let colorLight = lightColorWell.color.hexString
    let colorDark = darkColorWell.color.hexString

    do {
        _ = try db.createTag(name: name, colorLight: colorLight, colorDark: colorDark)
        reload()
    } catch {
        let errorAlert = NSAlert()
        errorAlert.messageText = "Ошибка"
        errorAlert.informativeText = "Тег с таким именем уже существует."
        errorAlert.runModal()
    }
}
```

**Step 4: Add NSColor.hexString extension**

Add to `EmpTracking/Extensions/NSColor+Hex.swift`:

```swift
extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.deviceRGB) else { return "#000000" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
```

**Step 5: Commit**

```bash
git add EmpTracking/Views/TimelineViewController.swift EmpTracking/Extensions/NSColor+Hex.swift
git commit -m "add tag assignment menu and tag creation form in timeline"
```

---

### Task 8: DetailView — add Apps/Tags segment and session tag menu

**Files:**
- Modify: `EmpTracking/Views/DetailViewController.swift`
- Modify: `EmpTracking/Views/DetailCellView.swift`

**Step 1: Add segmented control and tag mode to DetailViewController**

Replace full content of `EmpTracking/Views/DetailViewController.swift`:

```swift
import Cocoa

final class DetailViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let db: DatabaseManager
    private var logs: [ActivityLog] = []
    private var tagSummaries: [TagSummary] = []
    private var appCache: [Int64: AppInfo] = [:]
    private var tagCache: [Int64: Tag] = [:]

    private enum Mode: Int { case apps = 0, tags = 1 }
    private var mode: Mode = .apps

    private let segmentedControl = NSSegmentedControl()
    private let headerLabel = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()

    init(db: DatabaseManager) {
        self.db = db
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 600))
        self.view = container

        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        container.addSubview(headerLabel)

        totalLabel.translatesAutoresizingMaskIntoConstraints = false
        totalLabel.font = .systemFont(ofSize: 12)
        totalLabel.textColor = .secondaryLabelColor
        container.addSubview(totalLabel)

        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.segmentCount = 2
        segmentedControl.setLabel("Приложения", forSegment: 0)
        segmentedControl.setLabel("Теги", forSegment: 1)
        segmentedControl.selectedSegment = 0
        segmentedControl.target = self
        segmentedControl.action = #selector(segmentChanged(_:))
        segmentedControl.segmentStyle = .rounded
        container.addSubview(segmentedControl)

        let column = NSTableColumn(identifier: .init("detail"))
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
        scrollView.drawsBackground = false
        tableView.backgroundColor = .clear
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            headerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),

            totalLabel.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
            totalLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            segmentedControl.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            segmentedControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        mode = Mode(rawValue: sender.selectedSegment) ?? .apps
        reload()
    }

    func reload() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        headerLabel.stringValue = formatter.string(from: Date())

        let since = Calendar.current.startOfDay(for: Date())

        do {
            switch mode {
            case .apps:
                logs = try db.fetchTodayLogs()
                for log in logs where appCache[log.appId] == nil {
                    appCache[log.appId] = try db.fetchAppInfo(appId: log.appId)
                }
                // Cache tags
                let allTags = try db.fetchAllTags()
                tagCache = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })

                let totalActive = logs.filter { !$0.isIdle }.reduce(0.0) {
                    $0 + $1.endTime.timeIntervalSince($1.startTime)
                }
                let hours = Int(totalActive) / 3600
                let minutes = (Int(totalActive) % 3600) / 60
                totalLabel.stringValue = "Активно: \(hours)ч \(minutes)мин"

            case .tags:
                tagSummaries = try db.fetchTagSummaries(from: since, to: Date())
                let total = tagSummaries.reduce(0.0) { $0 + $1.totalDuration }
                let hours = Int(total) / 3600
                let minutes = (Int(total) % 3600) / 60
                totalLabel.stringValue = "Активно: \(hours)ч \(minutes)мин"
            }
        } catch {
            print("Error fetching detail: \(error)")
        }

        tableView.reloadData()
    }

    // MARK: - NSTableViewDataSource

    nonisolated func numberOfRows(in tableView: NSTableView) -> Int {
        MainActor.assumeIsolated {
            switch mode {
            case .apps: return logs.count
            case .tags: return tagSummaries.count
            }
        }
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch mode {
        case .apps:
            let id = NSUserInterfaceItemIdentifier("DetailCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? DetailCellView)
                ?? DetailCellView()
            cell.identifier = id
            let log = logs[row]
            let appInfo = appCache[log.appId]
            let resolvedTag = resolveTag(log: log, appInfo: appInfo)
            cell.configure(log: log, appInfo: appInfo, tag: resolvedTag)
            return cell

        case .tags:
            let id = NSUserInterfaceItemIdentifier("TagCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? TagCellView)
                ?? TagCellView()
            cell.identifier = id
            cell.configure(summary: tagSummaries[row])
            return cell
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard mode == .apps else { return false }
        let log = logs[row]
        guard !log.isIdle else { return false }
        showSessionTagMenu(forLog: log, at: row)
        return false
    }

    // MARK: - Tag resolution

    private func resolveTag(log: ActivityLog, appInfo: AppInfo?) -> Tag? {
        if let tagId = log.tagId {
            return tagCache[tagId]
        }
        if let defaultTagId = appInfo?.defaultTagId {
            return tagCache[defaultTagId]
        }
        return nil
    }

    // MARK: - Session tag menu

    private func showSessionTagMenu(forLog log: ActivityLog, at row: Int) {
        let menu = NSMenu()

        let tags: [Tag]
        let appInfo = appCache[log.appId]
        do {
            tags = try db.fetchAllTags()
        } catch {
            print("Error loading tags: \(error)")
            return
        }

        let resolvedTagId = log.tagId
        let isOverridden = log.tagId != nil

        // "App tag" item — reset to app default
        let appTagItem = NSMenuItem(title: "Тег приложения", action: #selector(sessionTagMenuClicked(_:)), keyEquivalent: "")
        appTagItem.target = self
        appTagItem.representedObject = SessionTagAction(logId: log.id, tagId: nil, isReset: true)
        if !isOverridden { appTagItem.state = .on }
        menu.addItem(appTagItem)

        // "No tag" — explicitly null
        let noTagItem = NSMenuItem(title: "Без тега", action: #selector(sessionTagMenuClicked(_:)), keyEquivalent: "")
        noTagItem.target = self
        noTagItem.representedObject = SessionTagAction(logId: log.id, tagId: Int64(-1), isReset: false)
        menu.addItem(noTagItem)

        if !tags.isEmpty {
            menu.addItem(.separator())
        }

        for tag in tags {
            let item = NSMenuItem(title: tag.name, action: #selector(sessionTagMenuClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = SessionTagAction(logId: log.id, tagId: tag.id, isReset: false)
            if resolvedTagId == tag.id { item.state = .on }

            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let color = NSColor(hex: isDark ? tag.colorDark : tag.colorLight)
            let dot = NSAttributedString(string: "● ", attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 13)])
            let name = NSAttributedString(string: tag.name, attributes: [.font: NSFont.systemFont(ofSize: 13)])
            let title = NSMutableAttributedString()
            title.append(dot)
            title.append(name)
            item.attributedTitle = title

            menu.addItem(item)
        }

        menu.addItem(.separator())

        let createItem = NSMenuItem(title: "Создать тег...", action: #selector(createTagFromDetail(_:)), keyEquivalent: "")
        createItem.target = self
        menu.addItem(createItem)

        let rect = tableView.rect(ofRow: row)
        menu.popUp(positioning: nil, at: NSPoint(x: rect.midX, y: rect.midY), in: tableView)
    }

    @objc private func sessionTagMenuClicked(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? SessionTagAction else { return }
        do {
            if action.isReset {
                try db.setSessionTag(logId: action.logId, tagId: nil)
            } else if action.tagId == Int64(-1) {
                // "No tag" — we need a way to explicitly set no tag
                // For now, set to nil (same as reset)
                try db.setSessionTag(logId: action.logId, tagId: nil)
            } else {
                try db.setSessionTag(logId: action.logId, tagId: action.tagId)
            }
            reload()
        } catch {
            print("Error setting session tag: \(error)")
        }
    }

    @objc private func createTagFromDetail(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Создать тег"
        alert.addButton(withTitle: "Создать")
        alert.addButton(withTitle: "Отмена")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))

        let nameField = NSTextField(frame: NSRect(x: 0, y: 70, width: 300, height: 24))
        nameField.placeholderString = "Название тега"
        container.addSubview(nameField)

        let lightLabel = NSTextField(labelWithString: "Светлая:")
        lightLabel.frame = NSRect(x: 0, y: 35, width: 60, height: 20)
        container.addSubview(lightLabel)

        let lightColorWell = NSColorWell(frame: NSRect(x: 65, y: 30, width: 50, height: 30))
        lightColorWell.color = .systemGreen
        container.addSubview(lightColorWell)

        let darkLabel = NSTextField(labelWithString: "Тёмная:")
        darkLabel.frame = NSRect(x: 150, y: 35, width: 60, height: 20)
        container.addSubview(darkLabel)

        let darkColorWell = NSColorWell(frame: NSRect(x: 215, y: 30, width: 50, height: 30))
        darkColorWell.color = .systemGreen
        container.addSubview(darkColorWell)

        alert.accessoryView = container

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        do {
            _ = try db.createTag(name: name, colorLight: lightColorWell.color.hexString, colorDark: darkColorWell.color.hexString)
            reload()
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Ошибка"
            errorAlert.informativeText = "Тег с таким именем уже существует."
            errorAlert.runModal()
        }
    }
}

private struct SessionTagAction {
    let logId: Int64
    let tagId: Int64?
    let isReset: Bool
}
```

**Step 2: Update DetailCellView to show tag color dot**

Replace full content of `EmpTracking/Views/DetailCellView.swift`:

```swift
import Cocoa

final class DetailCellView: NSTableCellView {
    private let colorDot = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")

    private var hasTag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        colorDot.translatesAutoresizingMaskIntoConstraints = false
        colorDot.wantsLayer = true
        colorDot.layer?.cornerRadius = 4
        addSubview(colorDot)

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
        timeLabel.lineBreakMode = .byTruncatingTail
        addSubview(timeLabel)

        NSLayoutConstraint.activate([
            colorDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            colorDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            colorDot.widthAnchor.constraint(equalToConstant: 8),
            colorDot.heightAnchor.constraint(equalToConstant: 8),

            iconView.leadingAnchor.constraint(equalTo: colorDot.trailingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),

            timeLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            timeLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            timeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
        ])
    }

    func configure(log: ActivityLog, appInfo: AppInfo?, tag: Tag? = nil) {
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"

        let duration = log.endTime.timeIntervalSince(log.startTime)
        let minutes = max(1, Int(duration) / 60)

        if log.isIdle {
            titleLabel.stringValue = "Idle"
            titleLabel.textColor = .tertiaryLabelColor
            iconView.image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "Idle")
            iconView.contentTintColor = .tertiaryLabelColor
            colorDot.isHidden = true
        } else {
            let appName = appInfo?.appName ?? "Unknown"
            if let windowTitle = log.windowTitle, !windowTitle.isEmpty {
                titleLabel.stringValue = "\(appName) — \(windowTitle)"
            } else {
                titleLabel.stringValue = appName
            }
            titleLabel.textColor = .labelColor
            iconView.image = appInfo?.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: "App")
            iconView.contentTintColor = nil

            if let tag = tag {
                colorDot.isHidden = false
                let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let hex = isDark ? tag.colorDark : tag.colorLight
                colorDot.layer?.backgroundColor = NSColor(hex: hex).cgColor

                // Overridden tag: show border
                if log.tagId != nil {
                    colorDot.layer?.borderWidth = 1.5
                    colorDot.layer?.borderColor = NSColor.labelColor.cgColor
                } else {
                    colorDot.layer?.borderWidth = 0
                }
            } else {
                colorDot.isHidden = true
            }
        }

        let start = timeFmt.string(from: log.startTime)
        let end = timeFmt.string(from: log.endTime)
        timeLabel.stringValue = "\(start) – \(end) (\(minutes)мин)"
    }
}
```

**Step 3: Commit**

```bash
git add EmpTracking/Views/DetailViewController.swift EmpTracking/Views/DetailCellView.swift
git commit -m "add Apps/Tags segment and session tag menu in detail view"
```

---

### Task 9: Build and smoke test

**Step 1: Build the project**

Run: `xcodebuild build -project EmpTracking.xcodeproj -scheme EmpTracking -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 2: Run all tests**

Run: `xcodebuild test -project EmpTracking.xcodeproj -scheme EmpTracking -destination 'platform=macOS' 2>&1 | tail -30`
Expected: ALL TESTS PASS

**Step 3: Fix any compilation errors**

If build fails, fix errors and re-run until build succeeds and tests pass.

**Step 4: Final commit (if fixes were needed)**

```bash
git add -A
git commit -m "fix build issues for tag system"
```
