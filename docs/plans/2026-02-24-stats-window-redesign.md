# Stats Window Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace DetailViewController with a new StatsViewController featuring a Gantt timeline, donut chart, app list, and gradient metric cards — all using EmpDesignSystem v0.2.0 components.

**Architecture:** Single StatsViewController (NSViewController) owns a toolbar and a scroll view. The scroll view contains three visual sections stacked vertically: Gantt timeline, two-column layout (Applications 55% + Summary 45%). Charts use SwiftUI Charts in NSHostingView. All UI components from EmpUI_macOS where possible.

**Tech Stack:** AppKit, SwiftUI Charts, EmpUI_macOS (EmpText, EmpImage, EmpButton, EmpProgressBar, EmpInfoCard, EmpSegmentControl, colors, gradients, spacing)

**Design doc:** `docs/plans/2026-02-24-stats-window-redesign-design.md`

---

### Task 1: Add DatabaseManager query methods

We need two new methods: `fetchAppSummaries(from:to:)` (date range) and `fetchLongestSession(from:to:)`.

**Files:**
- Modify: `Sources/Services/DatabaseManager.swift`

**Step 1: Add `fetchAppSummaries(from:to:)` method**

Add after the existing `fetchAppSummaries(since:)` method (line ~306):

```swift
func fetchAppSummaries(from: Date, to: Date) throws -> [AppSummary] {
    let sql = """
        SELECT a.id, a.app_name, a.bundle_id, ai.icon,
               SUM(l.end_time - l.start_time) as total_duration
        FROM activity_logs l
        JOIN apps a ON a.id = l.app_id
        LEFT JOIN app_icons ai ON ai.app_id = a.id
        WHERE l.start_time >= ? AND l.start_time < ? AND l.is_idle = 0
        GROUP BY l.app_id
        ORDER BY total_duration DESC
    """
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }

    sqlite3_bind_double(stmt, 1, from.timeIntervalSince1970)
    sqlite3_bind_double(stmt, 2, to.timeIntervalSince1970)

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
```

**Step 2: Add `fetchLongestSession(from:to:)` method**

Add right after the method above:

```swift
func fetchLongestSession(from: Date, to: Date) throws -> TimeInterval {
    let sql = "SELECT MAX(end_time - start_time) FROM activity_logs WHERE start_time >= ? AND start_time < ? AND is_idle = 0"
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }

    sqlite3_bind_double(stmt, 1, from.timeIntervalSince1970)
    sqlite3_bind_double(stmt, 2, to.timeIntervalSince1970)

    if sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_type(stmt, 0) != SQLITE_NULL {
        return sqlite3_column_double(stmt, 0)
    }
    return 0
}
```

**Step 3: Add `fetchDistinctDeviceNames()` method**

Add right after:

```swift
func fetchDistinctDeviceNames() throws -> [String] {
    let sql = "SELECT DISTINCT device_name FROM remote_logs ORDER BY device_name"
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }

    var names: [String] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        names.append(String(cString: sqlite3_column_text(stmt, 0)))
    }
    return names
}
```

**Step 4: Verify build**

Run: `cd /Users/emp15/Developer/EmpTracking && xcodebuild build -workspace EmpTracking.xcworkspace -scheme EmpTracking -configuration Debug -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

---

### Task 2: Create DonutChartView (SwiftUI)

**Files:**
- Create: `Sources/Views/Stats/DonutChartView.swift`

**Step 1: Create the Stats directory**

Run: `mkdir -p /Users/emp15/Developer/EmpTracking/Sources/Views/Stats`

**Step 2: Write DonutChartView**

```swift
import SwiftUI
import Charts

struct DonutChartEntry: Identifiable {
    let id = UUID()
    let appName: String
    let duration: TimeInterval
    let color: Color
}

struct DonutChartView: View {
    let entries: [DonutChartEntry]
    let totalTime: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Chart(entries) { entry in
                    SectorMark(
                        angle: .value("Duration", entry.duration),
                        innerRadius: .ratio(0.6),
                        angularInset: 1
                    )
                    .foregroundStyle(entry.color)
                    .cornerRadius(3)
                }
                .frame(width: 136, height: 136)

                VStack(spacing: 2) {
                    Text(totalTime)
                        .font(.system(size: 18, weight: .bold))
                        .monospacedDigit()
                    Text("Total")
                        .font(.system(size: 9.5, weight: .medium))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 3) {
                ForEach(entries.prefix(5)) { entry in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(entry.color)
                            .frame(width: 7, height: 7)
                        Text(entry.appName)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        let total = entries.reduce(0) { $0 + $1.duration }
                        let pct = total > 0 ? Int(entry.duration / total * 100) : 0
                        Text("\(pct)%")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 16)
    }
}
```

**Step 3: Verify build**

Run: `cd /Users/emp15/Developer/EmpTracking && xcodebuild build -workspace EmpTracking.xcworkspace -scheme EmpTracking -configuration Debug -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

---

### Task 3: Update GanttChartView for new design

The existing `SessionGanttView` in `Sources/Views/SessionGanttView.swift` already works well. We'll reuse it as-is. The `GanttEntry` struct and `GanttColorPalette` stay unchanged. No new file needed — the current `SessionGanttView` is already what we need.

**Files:**
- No changes needed — existing `Sources/Views/SessionGanttView.swift` is reused

---

### Task 4: Create AppRowView

**Files:**
- Create: `Sources/Views/Stats/AppRowView.swift`

**Step 1: Write AppRowView**

This is a single row in the applications list, using DS components:

```swift
import Cocoa
import EmpUI_macOS

final class AppRowView: NSView {
    private let iconView = EmpImage()
    private let nameLabel = EmpText()
    private let timeLabel = EmpText()
    private let pctLabel = EmpText()
    private let progressBar = EmpProgressBar()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        let views = [iconView, nameLabel, timeLabel, pctLabel, progressBar]
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        pctLabel.setContentHuggingPriority(.required, for: .horizontal)
        pctLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let padding = EmpSpacing.xs.rawValue

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: padding),
            nameLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: padding),
            timeLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            pctLabel.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 5),
            pctLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            pctLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            pctLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),

            progressBar.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            progressBar.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            progressBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    func configure(summary: AppSummary, totalDuration: TimeInterval, color: Color) {
        let icon = summary.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: "App")!
        iconView.configure(with: EmpImage.ViewModel(
            common: CommonViewModel(corners: .init(radius: 6)),
            image: icon,
            size: CGSize(width: 26, height: 26),
            contentMode: .aspectFit
        ))

        nameLabel.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: summary.appName,
                font: .systemFont(ofSize: 12.5, weight: .medium),
                color: NSColor.Semantic.textPrimary
            )),
            numberOfLines: 1
        ))

        timeLabel.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: Self.formatDuration(summary.totalDuration),
                font: .systemFont(ofSize: 12.5, weight: .semibold),
                color: NSColor.Semantic.textPrimary
            )),
            numberOfLines: 1,
            alignment: .right
        ))

        let pct = totalDuration > 0 ? Int(summary.totalDuration / totalDuration * 100) : 0
        pctLabel.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: "\(pct)%",
                font: .systemFont(ofSize: 10.5),
                color: NSColor.Semantic.textTertiary
            )),
            numberOfLines: 1,
            alignment: .right
        ))

        let progress = totalDuration > 0 ? CGFloat(summary.totalDuration / totalDuration) : 0
        let nsColor = NSColor(color)
        progressBar.configure(with: EmpProgressBar.ViewModel(
            progress: progress,
            fillColor: nsColor,
            barHeight: 2.5
        ))
    }

    private static func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)min"
        } else {
            return "\(minutes)min"
        }
    }
}
```

**Step 2: Verify build**

Run build command.
Expected: BUILD SUCCEEDED

---

### Task 5: Create MetricsGridView

**Files:**
- Create: `Sources/Views/Stats/MetricsGridView.swift`

**Step 1: Write MetricsGridView**

```swift
import Cocoa
import EmpUI_macOS

final class MetricsGridView: NSView {
    private let totalTimeCard = EmpInfoCard()
    private let activeTimeCard = EmpInfoCard()
    private let longestSessionCard = EmpInfoCard()
    private let appsUsedCard = EmpInfoCard()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        let cards = [totalTimeCard, activeTimeCard, longestSessionCard, appsUsedCard]
        cards.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        let gap = EmpSpacing.xs.rawValue

        NSLayoutConstraint.activate([
            // Row 1
            totalTimeCard.topAnchor.constraint(equalTo: topAnchor),
            totalTimeCard.leadingAnchor.constraint(equalTo: leadingAnchor),

            activeTimeCard.topAnchor.constraint(equalTo: topAnchor),
            activeTimeCard.leadingAnchor.constraint(equalTo: totalTimeCard.trailingAnchor, constant: gap),
            activeTimeCard.trailingAnchor.constraint(equalTo: trailingAnchor),
            activeTimeCard.widthAnchor.constraint(equalTo: totalTimeCard.widthAnchor),

            // Row 2
            longestSessionCard.topAnchor.constraint(equalTo: totalTimeCard.bottomAnchor, constant: gap),
            longestSessionCard.leadingAnchor.constraint(equalTo: leadingAnchor),
            longestSessionCard.bottomAnchor.constraint(equalTo: bottomAnchor),
            longestSessionCard.heightAnchor.constraint(equalTo: totalTimeCard.heightAnchor),

            appsUsedCard.topAnchor.constraint(equalTo: activeTimeCard.bottomAnchor, constant: gap),
            appsUsedCard.leadingAnchor.constraint(equalTo: longestSessionCard.trailingAnchor, constant: gap),
            appsUsedCard.trailingAnchor.constraint(equalTo: trailingAnchor),
            appsUsedCard.bottomAnchor.constraint(equalTo: bottomAnchor),
            appsUsedCard.widthAnchor.constraint(equalTo: longestSessionCard.widthAnchor),
            appsUsedCard.heightAnchor.constraint(equalTo: longestSessionCard.heightAnchor),
        ])
    }

    struct Data {
        let totalTime: String
        let activeTime: String
        let longestSession: String
        let appsUsed: String
    }

    func configure(with data: Data) {
        totalTimeCard.configure(with: EmpInfoCard.Preset.gradient(
            subtitle: "Total Time",
            value: data.totalTime,
            gradient: .Preset.lavenderToSky
        ))

        activeTimeCard.configure(with: EmpInfoCard.Preset.gradient(
            subtitle: "Active Time",
            value: data.activeTime,
            gradient: .Preset.skyToMint
        ))

        longestSessionCard.configure(with: EmpInfoCard.Preset.gradient(
            subtitle: "Longest Session",
            value: data.longestSession,
            gradient: .Preset.peachToRose
        ))

        appsUsedCard.configure(with: EmpInfoCard.Preset.gradient(
            subtitle: "Apps Used",
            value: data.appsUsed,
            gradient: .Preset.lavenderToLilac
        ))
    }
}
```

**Step 2: Verify build**

---

### Task 6: Create StatsViewController

This is the main controller that ties everything together.

**Files:**
- Create: `Sources/Views/Stats/StatsViewController.swift`

**Step 1: Write StatsViewController**

```swift
import Cocoa
import SwiftUI
import EmpUI_macOS

final class StatsViewController: NSViewController {
    private let db: DatabaseManager
    private let deviceId: String

    // State
    private enum TimelineMode: Int { case day = 0, week = 1 }
    private var timelineMode: TimelineMode = .day
    private var anchorDate = Date()
    private var deviceFilter: String? // nil = all, "this" = this mac, or device name

    // Data
    private var appSummaries: [AppSummary] = []
    private var localLogs: [ActivityLog] = []
    private var remoteLogs: [RemoteLog] = []
    private var appCache: [Int64: AppInfo] = [:]

    // MARK: - UI Elements

    // Toolbar
    private let dateLabel = EmpText()
    private let segmentControl = EmpSegmentControl()
    private let prevButton = EmpButton()
    private let calendarButton = EmpButton()
    private let nextButton = EmpButton()
    private let devicePopup = NSPopUpButton()
    private var calendarPopover: NSPopover?

    // Content
    private let contentScrollView = NSScrollView()
    private let contentView = NSView() // documentView of scroll

    // Timeline section
    private let timelineSectionLabel = EmpText()
    private let timelineCard = NSView()
    private var ganttHostingView: NSHostingView<SessionGanttView>!

    // Applications section
    private let appsSectionLabel = EmpText()
    private let appsCard = NSView()
    private var donutHostingView: NSHostingView<DonutChartView>!
    private let appsListStack = NSStackView()
    private let appsListScrollView = NSScrollView()

    // Summary section
    private let summarySectionLabel = EmpText()
    private let metricsGrid = MetricsGridView()

    // MARK: - Init

    init(db: DatabaseManager, deviceId: String = "") {
        self.db = db
        self.deviceId = deviceId
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Load View

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 820))
        container.wantsLayer = true
        self.view = container

        setupToolbar(in: container)
        setupContent(in: container)
    }

    // MARK: - Toolbar Setup

    private func setupToolbar(in container: NSView) {
        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.wantsLayer = true
        container.addSubview(toolbar)

        // Toolbar bottom border
        let border = NSView()
        border.translatesAutoresizingMaskIntoConstraints = false
        border.wantsLayer = true
        border.layer?.backgroundColor = NSColor.Semantic.borderSubtle.cgColor
        toolbar.addSubview(border)

        // Date label
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(dateLabel)

        // Segment control
        segmentControl.translatesAutoresizingMaskIntoConstraints = false
        segmentControl.configure(with: EmpSegmentControl.Preset.default(segments: ["Day", "Week"]))
        segmentControl.onSelectionChanged = { [weak self] index in
            self?.timelineMode = TimelineMode(rawValue: index) ?? .day
            self?.reload()
        }
        toolbar.addSubview(segmentControl)

        // Nav buttons
        prevButton.translatesAutoresizingMaskIntoConstraints = false
        prevButton.configure(with: EmpButton.Preset.ghost(
            .primary,
            content: .init(center: .text("\u{2039}")),
            size: .small
        ))
        prevButton.action = { [weak self] in self?.navigate(by: -1) }
        toolbar.addSubview(prevButton)

        calendarButton.translatesAutoresizingMaskIntoConstraints = false
        calendarButton.configure(with: EmpButton.Preset.ghost(
            .primary,
            content: .init(center: .icon(NSImage(systemSymbolName: "calendar", accessibilityDescription: "Calendar")!)),
            size: .small
        ))
        calendarButton.action = { [weak self] in self?.showCalendar() }
        toolbar.addSubview(calendarButton)

        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.configure(with: EmpButton.Preset.ghost(
            .primary,
            content: .init(center: .text("\u{203A}")),
            size: .small
        ))
        nextButton.action = { [weak self] in self?.navigate(by: 1) }
        toolbar.addSubview(nextButton)

        // Device filter
        devicePopup.translatesAutoresizingMaskIntoConstraints = false
        devicePopup.controlSize = .small
        devicePopup.font = .systemFont(ofSize: 12)
        devicePopup.target = self
        devicePopup.action = #selector(deviceFilterChanged(_:))
        toolbar.addSubview(devicePopup)

        let hp = EmpSpacing.l.rawValue // 20
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 52),

            border.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            border.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),

            dateLabel.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: hp),
            dateLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            segmentControl.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            segmentControl.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),

            prevButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            prevButton.leadingAnchor.constraint(equalTo: segmentControl.trailingAnchor, constant: EmpSpacing.m.rawValue),

            calendarButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            calendarButton.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: EmpSpacing.xxs.rawValue),

            nextButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            nextButton.leadingAnchor.constraint(equalTo: calendarButton.trailingAnchor, constant: EmpSpacing.xxs.rawValue),

            devicePopup.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            devicePopup.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -hp),
        ])
    }

    // MARK: - Content Setup

    private func setupContent(in container: NSView) {
        let hp = EmpSpacing.l.rawValue
        let sectionGap = EmpSpacing.s.rawValue
        let cardGap = EmpSpacing.m.rawValue

        // Scroll view
        contentScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView.hasVerticalScroller = true
        contentScrollView.hasHorizontalScroller = false
        contentScrollView.drawsBackground = false
        container.addSubview(contentScrollView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView.documentView = contentView

        NSLayoutConstraint.activate([
            contentScrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 52),
            contentScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentScrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: contentScrollView.contentView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: contentScrollView.contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentScrollView.contentView.trailingAnchor),
            contentView.widthAnchor.constraint(equalTo: contentScrollView.widthAnchor),
        ])

        // --- TIMELINE SECTION ---
        timelineSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(timelineSectionLabel)
        timelineSectionLabel.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: "TIMELINE",
                font: .systemFont(ofSize: 11, weight: .semibold),
                color: NSColor.Semantic.textTertiary
            )),
            numberOfLines: 1
        ))

        timelineCard.translatesAutoresizingMaskIntoConstraints = false
        timelineCard.wantsLayer = true
        timelineCard.layer?.cornerRadius = 12
        timelineCard.layer?.cornerCurve = .continuous
        contentView.addSubview(timelineCard)

        ganttHostingView = NSHostingView(rootView: SessionGanttView(entries: []))
        ganttHostingView.translatesAutoresizingMaskIntoConstraints = false
        timelineCard.addSubview(ganttHostingView)

        NSLayoutConstraint.activate([
            timelineSectionLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: cardGap),
            timelineSectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: hp),

            timelineCard.topAnchor.constraint(equalTo: timelineSectionLabel.bottomAnchor, constant: sectionGap - 4),
            timelineCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: hp),
            timelineCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -hp),
            timelineCard.heightAnchor.constraint(equalToConstant: 280),

            ganttHostingView.topAnchor.constraint(equalTo: timelineCard.topAnchor, constant: 8),
            ganttHostingView.leadingAnchor.constraint(equalTo: timelineCard.leadingAnchor, constant: 8),
            ganttHostingView.trailingAnchor.constraint(equalTo: timelineCard.trailingAnchor, constant: -8),
            ganttHostingView.bottomAnchor.constraint(equalTo: timelineCard.bottomAnchor, constant: -8),
        ])

        // --- TWO-COLUMN LAYOUT ---
        // Left column: Applications
        appsSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(appsSectionLabel)
        appsSectionLabel.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: "APPLICATIONS",
                font: .systemFont(ofSize: 11, weight: .semibold),
                color: NSColor.Semantic.textTertiary
            )),
            numberOfLines: 1
        ))

        appsCard.translatesAutoresizingMaskIntoConstraints = false
        appsCard.wantsLayer = true
        appsCard.layer?.cornerRadius = 12
        appsCard.layer?.cornerCurve = .continuous
        contentView.addSubview(appsCard)

        // Donut chart (left side of apps card)
        donutHostingView = NSHostingView(rootView: DonutChartView(entries: [], totalTime: "0min"))
        donutHostingView.translatesAutoresizingMaskIntoConstraints = false
        appsCard.addSubview(donutHostingView)

        // Divider between donut and list
        let divider = NSView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.Semantic.borderSubtle.cgColor
        appsCard.addSubview(divider)

        // Apps list (right side of apps card)
        appsListStack.orientation = .vertical
        appsListStack.spacing = 1
        appsListStack.translatesAutoresizingMaskIntoConstraints = false

        appsListScrollView.translatesAutoresizingMaskIntoConstraints = false
        appsListScrollView.documentView = appsListStack
        appsListScrollView.hasVerticalScroller = true
        appsListScrollView.drawsBackground = false
        appsCard.addSubview(appsListScrollView)

        // Right column: Summary
        summarySectionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(summarySectionLabel)
        summarySectionLabel.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: "SUMMARY",
                font: .systemFont(ofSize: 11, weight: .semibold),
                color: NSColor.Semantic.textTertiary
            )),
            numberOfLines: 1
        ))

        metricsGrid.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(metricsGrid)

        let twoColTop = timelineCard.bottomAnchor

        NSLayoutConstraint.activate([
            // Apps section label
            appsSectionLabel.topAnchor.constraint(equalTo: twoColTop, constant: cardGap),
            appsSectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: hp),

            // Apps card — 55% width
            appsCard.topAnchor.constraint(equalTo: appsSectionLabel.bottomAnchor, constant: sectionGap - 4),
            appsCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: hp),
            appsCard.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.55, constant: -(hp + cardGap / 2)),
            appsCard.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -cardGap),

            // Donut inside apps card
            donutHostingView.topAnchor.constraint(equalTo: appsCard.topAnchor),
            donutHostingView.leadingAnchor.constraint(equalTo: appsCard.leadingAnchor),
            donutHostingView.bottomAnchor.constraint(equalTo: appsCard.bottomAnchor),
            donutHostingView.widthAnchor.constraint(equalToConstant: 180),

            // Divider
            divider.topAnchor.constraint(equalTo: appsCard.topAnchor, constant: 8),
            divider.bottomAnchor.constraint(equalTo: appsCard.bottomAnchor, constant: -8),
            divider.leadingAnchor.constraint(equalTo: donutHostingView.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            // Apps list
            appsListScrollView.topAnchor.constraint(equalTo: appsCard.topAnchor, constant: 8),
            appsListScrollView.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            appsListScrollView.trailingAnchor.constraint(equalTo: appsCard.trailingAnchor),
            appsListScrollView.bottomAnchor.constraint(equalTo: appsCard.bottomAnchor, constant: -8),

            // Apps list stack width
            appsListStack.widthAnchor.constraint(equalTo: appsListScrollView.widthAnchor),

            // Summary section label
            summarySectionLabel.topAnchor.constraint(equalTo: twoColTop, constant: cardGap),
            summarySectionLabel.leadingAnchor.constraint(equalTo: appsCard.trailingAnchor, constant: cardGap),

            // Metrics grid
            metricsGrid.topAnchor.constraint(equalTo: summarySectionLabel.bottomAnchor, constant: sectionGap - 4),
            metricsGrid.leadingAnchor.constraint(equalTo: appsCard.trailingAnchor, constant: cardGap),
            metricsGrid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -hp),
            metricsGrid.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -cardGap),
        ])
    }

    // MARK: - Lifecycle

    override func viewWillAppear() {
        super.viewWillAppear()
        setupDeviceFilter()
        reload()
    }

    override func viewDidChangeEffectiveAppearance() {
        updateCardColors()
    }

    // MARK: - Device Filter

    private func setupDeviceFilter() {
        devicePopup.removeAllItems()
        devicePopup.addItem(withTitle: "All devices")
        devicePopup.addItem(withTitle: "This Mac")

        if let devices = try? db.fetchDistinctDeviceNames() {
            for name in devices {
                devicePopup.addItem(withTitle: name)
            }
        }
        devicePopup.selectItem(at: 1) // default: This Mac
        deviceFilter = "this"
    }

    @objc private func deviceFilterChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        if index == 0 {
            deviceFilter = nil
        } else if index == 1 {
            deviceFilter = "this"
        } else {
            deviceFilter = sender.titleOfSelectedItem
        }
        reload()
    }

    // MARK: - Navigation

    private func navigate(by delta: Int) {
        let cal = Calendar.current
        switch timelineMode {
        case .day:
            anchorDate = cal.date(byAdding: .day, value: delta, to: anchorDate)!
        case .week:
            anchorDate = cal.date(byAdding: .weekOfYear, value: delta, to: anchorDate)!
        }
        reload()
    }

    private func showCalendar() {
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
        calendarPopover = popover

        picker.target = self
        picker.action = #selector(calendarDatePicked(_:))
    }

    @objc private func calendarDatePicked(_ sender: NSDatePicker) {
        anchorDate = sender.dateValue
        calendarPopover?.close()
        calendarPopover = nil
        reload()
    }

    // MARK: - Date Helpers

    private func currentRange() -> (Date, Date) {
        let cal = Calendar.current
        switch timelineMode {
        case .day:
            let start = cal.startOfDay(for: anchorDate)
            return (start, start.addingTimeInterval(86400))
        case .week:
            var start = cal.startOfDay(for: anchorDate)
            let weekday = cal.component(.weekday, from: start)
            let daysFromMonday = (weekday + 5) % 7
            start = cal.date(byAdding: .day, value: -daysFromMonday, to: start)!
            let end = cal.date(byAdding: .day, value: 7, to: start)!
            return (start, end)
        }
    }

    // MARK: - Reload

    func reload() {
        let (rangeStart, rangeEnd) = currentRange()
        updateDateLabel()
        updateCardColors()
        loadData(from: rangeStart, to: rangeEnd)
        updateGantt(from: rangeStart, to: rangeEnd)
        updateDonutAndAppsList()
        updateMetrics(from: rangeStart, to: rangeEnd)
    }

    private func updateDateLabel() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")

        let text: String
        switch timelineMode {
        case .day:
            formatter.dateFormat = "EEEE, MMMM d"
            text = formatter.string(from: anchorDate)
        case .week:
            let (start, end) = currentRange()
            formatter.dateFormat = "MMM d"
            let startStr = formatter.string(from: start)
            let endStr = formatter.string(from: end.addingTimeInterval(-1))
            text = "\(startStr) – \(endStr)"
        }

        dateLabel.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: text,
                font: .systemFont(ofSize: 14, weight: .semibold),
                color: NSColor.Semantic.textPrimary
            )),
            numberOfLines: 1
        ))
    }

    private func updateCardColors() {
        let bg = NSColor.Semantic.backgroundSecondary
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            timelineCard.layer?.backgroundColor = bg.cgColor
            appsCard.layer?.backgroundColor = bg.cgColor
        }
    }

    // MARK: - Data Loading

    private func loadData(from: Date, to: Date) {
        do {
            appSummaries = try db.fetchAppSummaries(from: from, to: to)

            if deviceFilter == nil || deviceFilter == "this" {
                localLogs = try db.fetchLogs(from: from, to: to)
                for log in localLogs where appCache[log.appId] == nil {
                    appCache[log.appId] = try db.fetchAppInfo(appId: log.appId)
                }
            } else {
                localLogs = []
            }

            if deviceFilter == nil || (deviceFilter != "this") {
                remoteLogs = try db.fetchRemoteLogs(from: from, to: to)
            } else {
                remoteLogs = []
            }
        } catch {
            print("Error loading data: \(error)")
        }
    }

    // MARK: - Gantt Update

    private func updateGantt(from: Date, to: Date) {
        var entries: [GanttEntry] = []

        if deviceFilter == nil || deviceFilter == "this" {
            for log in localLogs where !log.isIdle {
                let appInfo = appCache[log.appId]
                let appName = appInfo?.appName ?? "Unknown"
                entries.append(GanttEntry(
                    appName: appName,
                    startTime: log.startTime,
                    endTime: log.endTime,
                    colorIndex: GanttColorPalette.colorIndex(for: appName)
                ))
            }
        }

        if deviceFilter == nil || deviceFilter != "this" {
            for log in remoteLogs where !log.isIdle {
                entries.append(GanttEntry(
                    appName: log.appName,
                    startTime: log.startTime,
                    endTime: log.endTime,
                    colorIndex: GanttColorPalette.colorIndex(for: log.appName)
                ))
            }
        }

        ganttHostingView.rootView = SessionGanttView(entries: entries)
    }

    // MARK: - Donut + Apps List

    private func updateDonutAndAppsList() {
        let totalDuration = appSummaries.reduce(0.0) { $0 + $1.totalDuration }

        // Donut chart
        let donutEntries = appSummaries.map { summary in
            DonutChartEntry(
                appName: summary.appName,
                duration: summary.totalDuration,
                color: GanttColorPalette.color(for: summary.appName)
            )
        }
        donutHostingView.rootView = DonutChartView(
            entries: donutEntries,
            totalTime: formatDuration(totalDuration)
        )

        // Apps list
        appsListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for summary in appSummaries {
            let row = AppRowView()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.configure(
                summary: summary,
                totalDuration: totalDuration,
                color: GanttColorPalette.color(for: summary.appName)
            )
            appsListStack.addArrangedSubview(row)
        }
    }

    // MARK: - Metrics

    private func updateMetrics(from: Date, to: Date) {
        let totalDuration = appSummaries.reduce(0.0) { $0 + $1.totalDuration }
        let longestSession = (try? db.fetchLongestSession(from: from, to: to)) ?? 0
        let appsCount = appSummaries.count

        // Active time = total (we already exclude idle in fetchAppSummaries)
        metricsGrid.configure(with: MetricsGridView.Data(
            totalTime: formatDuration(totalDuration),
            activeTime: formatDuration(totalDuration),
            longestSession: formatDuration(longestSession),
            appsUsed: "\(appsCount)"
        ))
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)min"
        } else {
            return "\(minutes)min"
        }
    }
}
```

**Step 2: Verify build**

---

### Task 7: Wire StatsViewController into AppDelegate

**Files:**
- Modify: `Sources/AppDelegate.swift` (lines 129-152: `showDetailWindow()`)

**Step 1: Replace showDetailWindow() to use StatsViewController**

Replace the `showDetailWindow()` method body:

```swift
private func showDetailWindow() {
    popover.performClose(nil)

    if let window = detailWindow {
        (window.contentViewController as? StatsViewController)?.reload()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        return
    }

    let deviceId = (try? db.getOrCreateDeviceId()) ?? ""
    let statsVC = StatsViewController(db: db, deviceId: deviceId)
    let window = NSWindow(contentViewController: statsVC)
    window.title = "Statistics"
    window.setContentSize(NSSize(width: 1280, height: 820))
    window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
    window.minSize = NSSize(width: 900, height: 600)
    window.center()
    window.isReleasedWhenClosed = false
    self.detailWindow = window

    window.makeKeyAndOrderFront(nil)
    NSApp.activate()
}
```

**Step 2: Verify build and run**

Run: `cd /Users/emp15/Developer/EmpTracking && xcodebuild build -workspace EmpTracking.xcworkspace -scheme EmpTracking -configuration Debug -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

---

### Task 8: Regenerate Tuist project and full build test

Since we added new files in `Sources/Views/Stats/`, Tuist's `sources: ["Sources/**"]` glob should pick them up automatically, but we need to regenerate:

**Step 1: Regenerate project**

Run: `cd /Users/emp15/Developer/EmpTracking && tuist generate`

**Step 2: Full build**

Run: `cd /Users/emp15/Developer/EmpTracking && xcodebuild build -workspace EmpTracking.xcworkspace -scheme EmpTracking -configuration Debug 2>&1 | tail -20`

**Step 3: Fix any compilation errors**

Address any issues from the build.

---

### Task 9: Visual polish and theme support

**Files:**
- Modify: `Sources/Views/Stats/StatsViewController.swift`

**Step 1: Add appearance observation for theme changes**

Add property and setup in `viewDidAppear`:

```swift
private var appearanceObservation: NSKeyValueObservation?

override func viewDidAppear() {
    super.viewDidAppear()
    if appearanceObservation == nil {
        appearanceObservation = view.observe(\.effectiveAppearance) { [weak self] _, _ in
            self?.updateCardColors()
            self?.reload()
        }
    }
}
```

**Step 2: Ensure divider color updates on theme change**

In `updateCardColors()`, also update the divider:

```swift
// Find and update divider color
for subview in appsCard.subviews where subview != donutHostingView && subview != appsListScrollView {
    subview.layer?.backgroundColor = NSColor.Semantic.borderSubtle.cgColor
}
```

**Step 3: Verify build and test both light/dark themes**

---

### Task 10: Remove tag UI from TimelineViewController popover

**Files:**
- Modify: `Sources/Views/TimelineViewController.swift`

**Step 1: Remove `tableView(_:shouldSelectRow:)` method** (lines 184-188)

Replace with:
```swift
func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    return false
}
```

**Step 2: Remove tag menu methods**

Delete the entire `showTagMenu(forAppId:at:)` method, `tagMenuItemClicked(_:)`, and `createTagClicked(_:)` methods (lines 192-303).

**Step 3: Verify build**
