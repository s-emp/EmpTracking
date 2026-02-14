# Dashboard Timeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a timeline bar chart with date navigation to the top of the Detail window, replacing the current flat session list with a richer, time-aware dashboard.

**Architecture:** NSCollectionView-based timeline with custom-draw cells, date navigation header, and Day/Week/Month mode switcher. Data flows from two new DatabaseManager query methods through DetailViewController into the collection view. Clicking a cell filters the existing session table.

**Tech Stack:** Swift, AppKit (NSCollectionView, NSView custom draw, NSDatePicker), SQLite3

---

### Task 1: Add `fetchHourlyTagSummaries` to DatabaseManager

**Files:**
- Modify: `EmpTracking/Services/DatabaseManager.swift:370` (after `fetchTagSummaries`)
- Test: `EmpTrackingTests/EmpTrackingTests.swift`

**Step 1: Write the failing test**

Add to `EmpTrackingTests.swift` before the closing `}` of `DatabaseManagerTests` and after the `fetchesTagSummaries` test:

```swift
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
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project EmpTracking.xcodeproj -scheme EmpTracking -only-testing:"EmpTrackingTests/DatabaseManagerTests/fetchesHourlyTagSummaries" 2>&1 | tail -20`
Expected: FAIL — `fetchHourlyTagSummaries` does not exist.

**Step 3: Add TagSlotDuration struct and implement the method**

First, add the return type struct near top of `DatabaseManager.swift` (before the class definition):

```swift
struct TagSlotDuration {
    let tagId: Int64?
    let duration: TimeInterval
}
```

Then add the method to `DatabaseManager`, after `fetchTagSummaries(from:to:)` (around line 409):

```swift
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
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project EmpTracking.xcodeproj -scheme EmpTracking -only-testing:"EmpTrackingTests/DatabaseManagerTests/fetchesHourlyTagSummaries" 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add EmpTracking/Services/DatabaseManager.swift EmpTrackingTests/EmpTrackingTests.swift
git commit -m "add fetchHourlyTagSummaries to DatabaseManager with tests"
```

---

### Task 2: Add `fetchDailyTagSummaries` to DatabaseManager

**Files:**
- Modify: `EmpTracking/Services/DatabaseManager.swift` (after `fetchHourlyTagSummaries`)
- Test: `EmpTrackingTests/EmpTrackingTests.swift`

**Step 1: Write the failing test**

Add to `EmpTrackingTests.swift` in `DatabaseManagerTests`:

```swift
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
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project EmpTracking.xcodeproj -scheme EmpTracking -only-testing:"EmpTrackingTests/DatabaseManagerTests/fetchesDailyTagSummaries" 2>&1 | tail -20`
Expected: FAIL — `fetchDailyTagSummaries` does not exist.

**Step 3: Implement the method**

Add to `DatabaseManager.swift` after `fetchHourlyTagSummaries`:

```swift
func fetchDailyTagSummaries(from: Date, to: Date) throws -> [Date: [TagSlotDuration]] {
    let sql = """
        SELECT date(l.start_time, 'unixepoch', 'localtime') as day,
               COALESCE(l.tag_id, a.default_tag_id) as resolved_tag_id,
               SUM(l.end_time - l.start_time) as total_duration
        FROM activity_logs l
        JOIN apps a ON a.id = l.app_id
        WHERE l.start_time >= ? AND l.start_time < ? AND l.is_idle = 0
        GROUP BY day, resolved_tag_id
        ORDER BY day, total_duration DESC
    """
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }

    sqlite3_bind_double(stmt, 1, from.timeIntervalSince1970)
    sqlite3_bind_double(stmt, 2, to.timeIntervalSince1970)

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    dateFormatter.timeZone = .current

    var result: [Date: [TagSlotDuration]] = [:]
    while sqlite3_step(stmt) == SQLITE_ROW {
        let dayStr = String(cString: sqlite3_column_text(stmt, 0))
        let tagId: Int64? = sqlite3_column_type(stmt, 1) != SQLITE_NULL
            ? sqlite3_column_int64(stmt, 1) : nil
        let duration = sqlite3_column_double(stmt, 2)

        if let dayDate = dateFormatter.date(from: dayStr) {
            result[dayDate, default: []].append(TagSlotDuration(tagId: tagId, duration: duration))
        }
    }
    return result
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project EmpTracking.xcodeproj -scheme EmpTracking -only-testing:"EmpTrackingTests/DatabaseManagerTests/fetchesDailyTagSummaries" 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add EmpTracking/Services/DatabaseManager.swift EmpTrackingTests/EmpTrackingTests.swift
git commit -m "add fetchDailyTagSummaries to DatabaseManager with tests"
```

---

### Task 3: Add `fetchLogs(from:to:)` to DatabaseManager

**Files:**
- Modify: `EmpTracking/Services/DatabaseManager.swift` (after `fetchTodayLogs`)
- Test: `EmpTrackingTests/EmpTrackingTests.swift`

**Step 1: Write the failing test**

```swift
@Test func fetchesLogsInRange() throws {
    let db = try makeTestDB()
    let appId = try db.insertOrGetApp(bundleId: "com.test.app", appName: "TestApp", iconPNG: nil)

    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let yesterday = today.addingTimeInterval(-86400)

    _ = try db.insertActivityLog(appId: appId, windowTitle: "Yesterday", startTime: yesterday.addingTimeInterval(3600), endTime: yesterday.addingTimeInterval(7200), isIdle: false)
    _ = try db.insertActivityLog(appId: appId, windowTitle: "Today", startTime: today.addingTimeInterval(3600), endTime: today.addingTimeInterval(7200), isIdle: false)

    let logs = try db.fetchLogs(from: yesterday, to: today)
    #expect(logs.count == 1)
    #expect(logs[0].windowTitle == "Yesterday")

    let allLogs = try db.fetchLogs(from: yesterday, to: today.addingTimeInterval(86400))
    #expect(allLogs.count == 2)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project EmpTracking.xcodeproj -scheme EmpTracking -only-testing:"EmpTrackingTests/DatabaseManagerTests/fetchesLogsInRange" 2>&1 | tail -20`
Expected: FAIL — `fetchLogs(from:to:)` does not exist.

**Step 3: Implement the method**

Add to `DatabaseManager.swift` after `fetchTodayLogs()` (around line 179):

```swift
func fetchLogs(from: Date, to: Date) throws -> [ActivityLog] {
    let sql = "SELECT id, app_id, window_title, start_time, end_time, is_idle, tag_id FROM activity_logs WHERE start_time >= ? AND start_time < ? ORDER BY start_time DESC"
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }

    sqlite3_bind_double(stmt, 1, from.timeIntervalSince1970)
    sqlite3_bind_double(stmt, 2, to.timeIntervalSince1970)

    var logs: [ActivityLog] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        logs.append(logFromStatement(stmt!))
    }
    return logs
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project EmpTracking.xcodeproj -scheme EmpTracking -only-testing:"EmpTrackingTests/DatabaseManagerTests/fetchesLogsInRange" 2>&1 | tail -20`
Expected: PASS

**Step 5: Run all tests to verify nothing broke**

Run: `xcodebuild test -project EmpTracking.xcodeproj -scheme EmpTracking 2>&1 | tail -30`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add EmpTracking/Services/DatabaseManager.swift EmpTrackingTests/EmpTrackingTests.swift
git commit -m "add fetchLogs(from:to:) to DatabaseManager with tests"
```

---

### Task 4: Create HourBarView custom draw NSView

**Files:**
- Create: `EmpTracking/Views/HourBarView.swift`

This view draws stacked colored rectangles from bottom up, proportional to tag durations.

**Step 1: Create HourBarView**

Create `EmpTracking/Views/HourBarView.swift`:

```swift
import Cocoa

final class HourBarView: NSView {
    /// Array of (color, fraction) where fraction is portion of bar height to fill.
    /// Sum of fractions should be <= 1.0. Drawn bottom-up.
    var segments: [(color: NSColor, fraction: CGFloat)] = [] {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds
        var y = rect.minY

        for segment in segments {
            let segmentHeight = rect.height * segment.fraction
            if segmentHeight < 0.5 { continue }
            let segmentRect = NSRect(x: rect.minX, y: y, width: rect.width, height: segmentHeight)
            segment.color.setFill()
            NSBezierPath(roundedRect: segmentRect, xRadius: 0, yRadius: 0).fill()
            y += segmentHeight
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
```

**Step 2: Add file to Xcode project**

Open `EmpTracking.xcodeproj` in Xcode or use the `add-file-to-xcode-project` script if available. The file must be added to the EmpTracking target.

Alternatively, from CLI:
```bash
# The file will be added to Xcode project in the integration task
```

**Step 3: Commit**

```bash
git add EmpTracking/Views/HourBarView.swift
git commit -m "add HourBarView custom draw NSView"
```

---

### Task 5: Create TimelineCell NSCollectionViewItem

**Files:**
- Create: `EmpTracking/Views/TimelineCell.swift`

Each cell contains a HourBarView (the colored bar) and an NSButton (the hour/day label).

**Step 1: Create TimelineCell**

Create `EmpTracking/Views/TimelineCell.swift`:

```swift
import Cocoa

final class TimelineCell: NSCollectionViewItem {
    let barView = HourBarView()
    let labelButton = NSButton()

    private var trackingArea: NSTrackingArea?

    var onTap: (() -> Void)?
    var isHighlighted: Bool = false {
        didSet {
            barView.layer?.borderWidth = isHighlighted ? 2 : 0
            barView.layer?.borderColor = NSColor.controlAccentColor.cgColor
        }
    }

    override func loadView() {
        let container = NSView()
        self.view = container

        barView.translatesAutoresizingMaskIntoConstraints = false
        barView.wantsLayer = true
        barView.layer?.cornerRadius = 3
        container.addSubview(barView)

        labelButton.translatesAutoresizingMaskIntoConstraints = false
        labelButton.isBordered = false
        labelButton.font = .systemFont(ofSize: 10)
        labelButton.target = self
        labelButton.action = #selector(labelTapped)
        container.addSubview(labelButton)

        NSLayoutConstraint.activate([
            barView.topAnchor.constraint(equalTo: container.topAnchor),
            barView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 1),
            barView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -1),
            barView.bottomAnchor.constraint(equalTo: labelButton.topAnchor, constant: -4),

            labelButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            labelButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            labelButton.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            labelButton.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateTrackingArea()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        if let existing = trackingArea {
            view.removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        labelButton.font = .systemFont(ofSize: 10, weight: .bold)
    }

    override func mouseExited(with event: NSEvent) {
        labelButton.font = .systemFont(ofSize: 10, weight: .regular)
    }

    @objc private func labelTapped() {
        onTap?()
    }

    func configure(label: String, segments: [(color: NSColor, fraction: CGFloat)]) {
        labelButton.title = label
        barView.segments = segments
    }
}
```

**Step 2: Commit**

```bash
git add EmpTracking/Views/TimelineCell.swift
git commit -m "add TimelineCell NSCollectionViewItem"
```

---

### Task 6: Restructure DetailViewController — add timeline and navigation

This is the largest task. It replaces the current simple header/segmented/table layout with: navigation header + timeline collection + existing table.

**Files:**
- Modify: `EmpTracking/Views/DetailViewController.swift` (major rewrite of `loadView()`, new properties, new methods)

**Step 1: Add new properties and enums**

Replace the current properties block (lines 3-17) with:

```swift
final class DetailViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
    private let db: DatabaseManager
    private var logs: [ActivityLog] = []
    private var filteredLogs: [ActivityLog] = []
    private var tagSummaries: [TagSummary] = []
    private var appCache: [Int64: AppInfo] = [:]
    private var tagCache: [Int64: Tag] = [:]

    private enum TableMode: Int { case apps = 0, tags = 1 }
    private var tableMode: TableMode = .apps

    private enum TimelineMode: Int { case day = 0, week = 1, month = 2 }
    private var timelineMode: TimelineMode = .day

    private var anchorDate = Date()
    private var selectedSlot: Int? = nil

    // Timeline data
    private var hourlyData: [Int: [TagSlotDuration]] = [:]
    private var dailyData: [Date: [TagSlotDuration]] = [:]
    private var slotDates: [Date] = [] // ordered dates for week/month mode

    // UI
    private let dateLabel = NSTextField(labelWithString: "")
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let calendarButton = NSButton()
    private let timelineModeControl = NSSegmentedControl()
    private let timelineCollectionView = NSCollectionView()
    private let timelineScrollView = NSScrollView()
    private let tableModeControl = NSSegmentedControl()
    private let headerLabel = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
```

**Step 2: Rewrite `loadView()` with new layout**

Replace the entire `loadView()` method:

```swift
override func loadView() {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 700))
    self.view = container

    // --- Navigation row ---
    dateLabel.translatesAutoresizingMaskIntoConstraints = false
    dateLabel.font = .systemFont(ofSize: 14, weight: .semibold)
    dateLabel.lineBreakMode = .byTruncatingTail
    dateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    container.addSubview(dateLabel)

    prevButton.translatesAutoresizingMaskIntoConstraints = false
    prevButton.bezelStyle = .inline
    prevButton.title = "‹"
    prevButton.font = .systemFont(ofSize: 16, weight: .medium)
    prevButton.target = self
    prevButton.action = #selector(prevTapped)
    container.addSubview(prevButton)

    calendarButton.translatesAutoresizingMaskIntoConstraints = false
    calendarButton.bezelStyle = .inline
    calendarButton.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Calendar")
    calendarButton.target = self
    calendarButton.action = #selector(calendarTapped)
    container.addSubview(calendarButton)

    nextButton.translatesAutoresizingMaskIntoConstraints = false
    nextButton.bezelStyle = .inline
    nextButton.title = "›"
    nextButton.font = .systemFont(ofSize: 16, weight: .medium)
    nextButton.target = self
    nextButton.action = #selector(nextTapped)
    container.addSubview(nextButton)

    timelineModeControl.translatesAutoresizingMaskIntoConstraints = false
    timelineModeControl.segmentCount = 3
    timelineModeControl.setLabel("День", forSegment: 0)
    timelineModeControl.setLabel("Неделя", forSegment: 1)
    timelineModeControl.setLabel("Месяц", forSegment: 2)
    timelineModeControl.selectedSegment = 0
    timelineModeControl.target = self
    timelineModeControl.action = #selector(timelineModeChanged(_:))
    timelineModeControl.segmentStyle = .rounded
    container.addSubview(timelineModeControl)

    // --- Timeline collection ---
    let flowLayout = NSCollectionViewFlowLayout()
    flowLayout.scrollDirection = .horizontal
    flowLayout.minimumInteritemSpacing = 0
    flowLayout.minimumLineSpacing = 0

    timelineCollectionView.collectionViewLayout = flowLayout
    timelineCollectionView.dataSource = self
    timelineCollectionView.delegate = self
    timelineCollectionView.register(TimelineCell.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("TimelineCell"))
    timelineCollectionView.backgroundColors = [.clear]

    timelineScrollView.translatesAutoresizingMaskIntoConstraints = false
    timelineScrollView.documentView = timelineCollectionView
    timelineScrollView.hasHorizontalScroller = false
    timelineScrollView.hasVerticalScroller = false
    timelineScrollView.drawsBackground = false
    container.addSubview(timelineScrollView)

    // --- Table mode + summary row ---
    tableModeControl.translatesAutoresizingMaskIntoConstraints = false
    tableModeControl.segmentCount = 2
    tableModeControl.setLabel("Приложения", forSegment: 0)
    tableModeControl.setLabel("Теги", forSegment: 1)
    tableModeControl.selectedSegment = 0
    tableModeControl.target = self
    tableModeControl.action = #selector(tableModeChanged(_:))
    tableModeControl.segmentStyle = .rounded
    container.addSubview(tableModeControl)

    totalLabel.translatesAutoresizingMaskIntoConstraints = false
    totalLabel.font = .systemFont(ofSize: 12)
    totalLabel.textColor = .secondaryLabelColor
    container.addSubview(totalLabel)

    // --- Session table ---
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

    let timelineHeight: CGFloat = 160

    NSLayoutConstraint.activate([
        // Navigation row
        dateLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
        dateLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),

        prevButton.centerYAnchor.constraint(equalTo: dateLabel.centerYAnchor),
        prevButton.leadingAnchor.constraint(greaterThanOrEqualTo: dateLabel.trailingAnchor, constant: 8),

        calendarButton.centerYAnchor.constraint(equalTo: dateLabel.centerYAnchor),
        calendarButton.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 2),

        nextButton.centerYAnchor.constraint(equalTo: dateLabel.centerYAnchor),
        nextButton.leadingAnchor.constraint(equalTo: calendarButton.trailingAnchor, constant: 2),

        timelineModeControl.centerYAnchor.constraint(equalTo: dateLabel.centerYAnchor),
        timelineModeControl.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 12),
        timelineModeControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

        // Timeline collection
        timelineScrollView.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 8),
        timelineScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
        timelineScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
        timelineScrollView.heightAnchor.constraint(equalToConstant: timelineHeight),

        // Table mode row
        tableModeControl.topAnchor.constraint(equalTo: timelineScrollView.bottomAnchor, constant: 8),
        tableModeControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),

        totalLabel.centerYAnchor.constraint(equalTo: tableModeControl.centerYAnchor),
        totalLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

        // Session table
        scrollView.topAnchor.constraint(equalTo: tableModeControl.bottomAnchor, constant: 8),
        scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
}
```

**Step 3: Add navigation action methods**

Add after `viewWillAppear`:

```swift
@objc private func prevTapped() {
    let cal = Calendar.current
    switch timelineMode {
    case .day: anchorDate = cal.date(byAdding: .day, value: -1, to: anchorDate)!
    case .week: anchorDate = cal.date(byAdding: .weekOfYear, value: -1, to: anchorDate)!
    case .month: anchorDate = cal.date(byAdding: .month, value: -1, to: anchorDate)!
    }
    selectedSlot = nil
    reload()
}

@objc private func nextTapped() {
    let cal = Calendar.current
    switch timelineMode {
    case .day: anchorDate = cal.date(byAdding: .day, value: 1, to: anchorDate)!
    case .week: anchorDate = cal.date(byAdding: .weekOfYear, value: 1, to: anchorDate)!
    case .month: anchorDate = cal.date(byAdding: .month, value: 1, to: anchorDate)!
    }
    selectedSlot = nil
    reload()
}

@objc private func calendarTapped() {
    let picker = NSDatePicker()
    picker.datePickerStyle = .clockAndCalendar
    picker.datePickerElements = .yearMonthDay
    picker.dateValue = anchorDate

    let vc = NSViewController()
    vc.view = picker
    vc.preferredContentSize = picker.fittingSize

    let popover = NSPopover()
    popover.contentViewController = vc
    popover.behavior = .transient
    popover.show(relativeTo: calendarButton.bounds, of: calendarButton, preferredEdge: .minY)

    picker.target = self
    picker.action = #selector(calendarDatePicked(_:))
}

@objc private func calendarDatePicked(_ sender: NSDatePicker) {
    anchorDate = sender.dateValue
    selectedSlot = nil
    reload()
    // Dismiss popover
    if let popover = (sender.window?.parent as? NSWindow)?.value(forKey: "popover") as? NSPopover {
        popover.close()
    }
}

@objc private func timelineModeChanged(_ sender: NSSegmentedControl) {
    timelineMode = TimelineMode(rawValue: sender.selectedSegment) ?? .day
    selectedSlot = nil
    reload()
}

@objc private func tableModeChanged(_ sender: NSSegmentedControl) {
    tableMode = TableMode(rawValue: sender.selectedSegment) ?? .apps
    reloadTable()
}
```

**Step 4: Commit this structural change**

```bash
git add EmpTracking/Views/DetailViewController.swift
git commit -m "restructure DetailViewController layout with timeline section"
```

---

### Task 7: Wire data loading and collection view

**Files:**
- Modify: `EmpTracking/Views/DetailViewController.swift`

**Step 1: Rewrite `reload()` method**

Replace existing `reload()` with:

```swift
func reload() {
    updateDateLabel()
    loadTimelineData()
    loadTableData()
    timelineCollectionView.reloadData()
    reloadTable()
}

private func updateDateLabel() {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    let cal = Calendar.current

    switch timelineMode {
    case .day:
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        dateLabel.stringValue = formatter.string(from: anchorDate).localizedCapitalized
    case .week:
        let (start, end) = weekRange(for: anchorDate)
        formatter.dateFormat = "d MMMM"
        let startStr = formatter.string(from: start)
        formatter.dateFormat = "d MMMM yyyy"
        let endStr = formatter.string(from: end.addingTimeInterval(-1))
        dateLabel.stringValue = "\(startStr) – \(endStr)"
    case .month:
        formatter.dateFormat = "LLLL yyyy"
        dateLabel.stringValue = formatter.string(from: anchorDate).localizedCapitalized
    }
}

private func loadTimelineData() {
    let cal = Calendar.current
    do {
        let allTags = try db.fetchAllTags()
        tagCache = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })

        switch timelineMode {
        case .day:
            hourlyData = try db.fetchHourlyTagSummaries(for: anchorDate)
            dailyData = [:]
            slotDates = []
        case .week:
            let (start, end) = weekRange(for: anchorDate)
            dailyData = try db.fetchDailyTagSummaries(from: start, to: end)
            hourlyData = [:]
            slotDates = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        case .month:
            let (start, end) = monthRange(for: anchorDate)
            dailyData = try db.fetchDailyTagSummaries(from: start, to: end)
            hourlyData = [:]
            let days = cal.dateComponents([.day], from: start, to: end).day ?? 30
            slotDates = (0..<days).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        }
    } catch {
        print("Error loading timeline data: \(error)")
    }
}

private func loadTableData() {
    let (rangeStart, rangeEnd) = currentRange()
    do {
        switch tableMode {
        case .apps:
            logs = try db.fetchLogs(from: rangeStart, to: rangeEnd)
            for log in logs where appCache[log.appId] == nil {
                appCache[log.appId] = try db.fetchAppInfo(appId: log.appId)
            }
            applySlotFilter()
        case .tags:
            tagSummaries = try db.fetchTagSummaries(from: rangeStart, to: rangeEnd)
        }
    } catch {
        print("Error loading table data: \(error)")
    }
}

private func applySlotFilter() {
    guard let slot = selectedSlot else {
        filteredLogs = logs
        return
    }
    let cal = Calendar.current
    switch timelineMode {
    case .day:
        filteredLogs = logs.filter { cal.component(.hour, from: $0.startTime) == slot }
    case .week, .month:
        guard slot < slotDates.count else { filteredLogs = logs; return }
        let dayStart = slotDates[slot]
        let dayEnd = dayStart.addingTimeInterval(86400)
        filteredLogs = logs.filter { $0.startTime >= dayStart && $0.startTime < dayEnd }
    }
}

private func reloadTable() {
    loadTableData()
    let active: TimeInterval
    switch tableMode {
    case .apps:
        active = filteredLogs.filter { !$0.isIdle }.reduce(0.0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
    case .tags:
        active = tagSummaries.reduce(0.0) { $0 + $1.totalDuration }
    }
    let hours = Int(active) / 3600
    let minutes = (Int(active) % 3600) / 60
    totalLabel.stringValue = "Активно: \(hours)ч \(minutes)мин"
    tableView.reloadData()
}
```

**Step 2: Add date range helper methods**

```swift
// MARK: - Date helpers

private func weekRange(for date: Date) -> (Date, Date) {
    let cal = Calendar.current
    var start = cal.startOfDay(for: date)
    // Roll back to Monday
    let weekday = cal.component(.weekday, from: start)
    let daysFromMonday = (weekday + 5) % 7
    start = cal.date(byAdding: .day, value: -daysFromMonday, to: start)!
    let end = cal.date(byAdding: .day, value: 7, to: start)!
    return (start, end)
}

private func monthRange(for date: Date) -> (Date, Date) {
    let cal = Calendar.current
    let comps = cal.dateComponents([.year, .month], from: date)
    let start = cal.date(from: comps)!
    let end = cal.date(byAdding: .month, value: 1, to: start)!
    return (start, end)
}

private func currentRange() -> (Date, Date) {
    let cal = Calendar.current
    switch timelineMode {
    case .day:
        let start = cal.startOfDay(for: anchorDate)
        return (start, start.addingTimeInterval(86400))
    case .week:
        return weekRange(for: anchorDate)
    case .month:
        return monthRange(for: anchorDate)
    }
}
```

**Step 3: Implement NSCollectionView data source and delegate**

```swift
// MARK: - NSCollectionViewDataSource

func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
    switch timelineMode {
    case .day: return 24
    case .week: return 7
    case .month: return slotDates.count
    }
}

func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
    let cell = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("TimelineCell"), for: indexPath) as! TimelineCell
    let slot = indexPath.item
    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

    let label: String
    let slotData: [TagSlotDuration]
    let maxDuration: TimeInterval

    switch timelineMode {
    case .day:
        label = "\(slot)"
        slotData = hourlyData[slot] ?? []
        maxDuration = 3600
    case .week:
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EE"
        label = slot < slotDates.count ? formatter.string(from: slotDates[slot]) : ""
        slotData = slot < slotDates.count ? (dailyData[slotDates[slot]] ?? []) : []
        maxDuration = 86400
    case .month:
        let cal = Calendar.current
        label = slot < slotDates.count ? "\(cal.component(.day, from: slotDates[slot]))" : ""
        slotData = slot < slotDates.count ? (dailyData[slotDates[slot]] ?? []) : []
        maxDuration = 86400
    }

    let totalActive = slotData.reduce(0.0) { $0 + $1.duration }
    let fillFraction = min(totalActive / maxDuration, 1.0)

    let segments: [(color: NSColor, fraction: CGFloat)] = slotData.map { entry in
        let color: NSColor
        if let tagId = entry.tagId, let tag = tagCache[tagId] {
            color = NSColor(hex: isDark ? tag.colorDark : tag.colorLight)
        } else {
            color = .systemGray
        }
        let fraction = CGFloat(fillFraction * (entry.duration / totalActive))
        return (color, fraction)
    }

    cell.configure(label: label, segments: segments)
    cell.isHighlighted = (selectedSlot == slot)
    cell.onTap = { [weak self] in
        guard let self else { return }
        if self.selectedSlot == slot {
            self.selectedSlot = nil
        } else {
            self.selectedSlot = slot
        }
        self.reloadTable()
        self.timelineCollectionView.reloadData()
    }

    return cell
}

// MARK: - NSCollectionViewDelegateFlowLayout

func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
    let count: CGFloat
    switch timelineMode {
    case .day: count = 24
    case .week: count = 7
    case .month: count = CGFloat(slotDates.count)
    }
    let width = max(collectionView.bounds.width / count, 14)
    return NSSize(width: width, height: collectionView.bounds.height)
}
```

**Step 4: Update table data source to use filteredLogs**

Update `numberOfRows` and `tableView(_:viewFor:row:)` to use `filteredLogs` instead of `logs` when in apps mode:

In `numberOfRows`:
```swift
nonisolated func numberOfRows(in tableView: NSTableView) -> Int {
    MainActor.assumeIsolated {
        switch tableMode {
        case .apps: return filteredLogs.count
        case .tags: return tagSummaries.count
        }
    }
}
```

In `tableView(_:viewFor:row:)` — replace `logs[row]` with `filteredLogs[row]`:
```swift
case .apps:
    let id = NSUserInterfaceItemIdentifier("DetailCell")
    let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? DetailCellView)
        ?? DetailCellView()
    cell.identifier = id
    let log = filteredLogs[row]
    let appInfo = appCache[log.appId]
    let resolvedTag = resolveTag(log: log, appInfo: appInfo)
    cell.configure(log: log, appInfo: appInfo, tag: resolvedTag)
    return cell
```

In `tableView(_:shouldSelectRow:)` — replace `logs[row]` with `filteredLogs[row]`:
```swift
func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    guard tableMode == .apps else { return false }
    let log = filteredLogs[row]
    guard !log.isIdle else { return false }
    showSessionTagMenu(forLog: log, at: row)
    return false
}
```

**Step 5: Rename old `segmentChanged` and remove old `headerLabel`**

Remove `headerLabel` property and its usage. Remove old `segmentChanged` method (replaced by `tableModeChanged` and `timelineModeChanged`).

**Step 6: Add files to Xcode project target**

Ensure `HourBarView.swift` and `TimelineCell.swift` are added to the EmpTracking target in the Xcode project. Run:

```bash
# Open .pbxproj and add file references, or use Xcode GUI
```

If using CLI, the implementer must add the new files to the Xcode project's Compile Sources build phase.

**Step 7: Build and verify**

Run: `xcodebuild build -project EmpTracking.xcodeproj -scheme EmpTracking 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 8: Run all tests**

Run: `xcodebuild test -project EmpTracking.xcodeproj -scheme EmpTracking 2>&1 | tail -30`
Expected: All tests PASS

**Step 9: Commit**

```bash
git add EmpTracking/Views/DetailViewController.swift
git commit -m "wire timeline data loading, collection view, and date navigation"
```

---

### Task 8: Theme support and polish

**Files:**
- Modify: `EmpTracking/Views/DetailViewController.swift`

**Step 1: Add appearance change handling**

Add to `DetailViewController`:

```swift
override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    timelineCollectionView.reloadData()
}
```

This causes all cells to re-query `isDark` and pick the correct tag color on theme change.

**Step 2: Build and manual test**

Run: `xcodebuild build -project EmpTracking.xcodeproj -scheme EmpTracking 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Run all tests**

Run: `xcodebuild test -project EmpTracking.xcodeproj -scheme EmpTracking 2>&1 | tail -30`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add EmpTracking/Views/DetailViewController.swift
git commit -m "add theme support for timeline bar colors"
```

---

### Task 9: Final integration — add new files to Xcode project

**Files:**
- Modify: `EmpTracking.xcodeproj/project.pbxproj`

The new files `HourBarView.swift` and `TimelineCell.swift` must be registered in the Xcode project file so they compile as part of the EmpTracking target.

**Step 1: Add files to project**

Use the Ruby `xcodeproj` gem or manually add to the pbxproj. The simplest reliable approach:

```bash
# If xcodeproj gem is available:
ruby -e '
require "xcodeproj"
proj = Xcodeproj::Project.open("EmpTracking.xcodeproj")
target = proj.targets.first
group = proj.main_group["EmpTracking"]["Views"]
["HourBarView.swift", "TimelineCell.swift"].each do |name|
  path = "EmpTracking/Views/#{name}"
  ref = group.new_file(path)
  target.source_build_phase.add_file_reference(ref)
end
proj.save
'
```

If `xcodeproj` is not available, open the project in Xcode and add files manually, or implement the equivalent pbxproj edits.

**Step 2: Clean build**

Run: `xcodebuild clean build -project EmpTracking.xcodeproj -scheme EmpTracking 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Run all tests**

Run: `xcodebuild test -project EmpTracking.xcodeproj -scheme EmpTracking 2>&1 | tail -30`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add EmpTracking.xcodeproj/project.pbxproj
git commit -m "add HourBarView and TimelineCell to Xcode project"
```
