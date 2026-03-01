import Cocoa
import SwiftUI
import EmpUI_macOS

private final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

final class StatsViewController: NSViewController {
    private let db: DatabaseManager
    private let deviceId: String

    // MARK: - State

    private enum TimelineMode: Int { case day = 0, week = 1 }
    private var timelineMode: TimelineMode = .day
    private var anchorDate = Date()
    private var deviceFilter: String? // nil = all, "this" = this mac, or specific device name
    private var groupingInterval: TimeInterval = 60
    private let ganttSelection = GanttSelectionState()
    private var allTags: [Tag] = []
    private var tagPopover: NSPopover?

    // MARK: - Data

    private var appSummaries: [AppSummary] = []
    private var localLogs: [ActivityLog] = []
    private var remoteLogs: [RemoteLog] = []
    private var appCache: [Int64: AppInfo] = [:]
    private var currentGanttEntries: [GanttEntry] = []

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
    private let contentView = NSView()
    private var toolbarBorder: NSView!
    private var appsDivider: NSView!

    // Timeline section
    private let timelineSectionLabel = EmpText()
    private let groupingSegmentControl = EmpSegmentControl()
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
        self.toolbarBorder = border

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

        let contentClipView = FlippedClipView()
        contentClipView.drawsBackground = false
        contentScrollView.contentView = contentClipView

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
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: contentScrollView.heightAnchor),
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

        groupingSegmentControl.translatesAutoresizingMaskIntoConstraints = false
        groupingSegmentControl.configure(with: EmpSegmentControl.Preset.default(segments: ["1m", "5m", "10m", "15m"]))
        groupingSegmentControl.onSelectionChanged = { [weak self] index in
            let intervals: [TimeInterval] = [60, 300, 600, 900]
            self?.groupingInterval = intervals[index]
            let range = self?.currentRange()
            if let range {
                self?.updateGantt(from: range.0, to: range.1)
            }
        }
        contentView.addSubview(groupingSegmentControl)

        timelineCard.translatesAutoresizingMaskIntoConstraints = false
        timelineCard.wantsLayer = true
        timelineCard.layer?.cornerRadius = 12
        timelineCard.layer?.cornerCurve = .continuous
        contentView.addSubview(timelineCard)

        ganttHostingView = NSHostingView(rootView: SessionGanttView(entries: []))
        ganttHostingView.translatesAutoresizingMaskIntoConstraints = false
        timelineCard.addSubview(ganttHostingView)

        let rightClick = NSClickGestureRecognizer(target: self, action: #selector(ganttRightClicked(_:)))
        rightClick.buttonMask = 0x2
        ganttHostingView.addGestureRecognizer(rightClick)

        NSLayoutConstraint.activate([
            timelineSectionLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: cardGap),
            timelineSectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: hp),

            groupingSegmentControl.centerYAnchor.constraint(equalTo: timelineSectionLabel.centerYAnchor),
            groupingSegmentControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -hp),

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
        donutHostingView = NSHostingView(rootView: DonutChartView(entries: []))
        donutHostingView.translatesAutoresizingMaskIntoConstraints = false
        appsCard.addSubview(donutHostingView)

        // Divider between donut and list
        let divider = NSView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.Semantic.borderSubtle.cgColor
        appsCard.addSubview(divider)
        self.appsDivider = divider

        // Apps list (right side of apps card)
        appsListStack.orientation = .vertical
        appsListStack.spacing = 1
        appsListStack.translatesAutoresizingMaskIntoConstraints = false

        appsListScrollView.translatesAutoresizingMaskIntoConstraints = false
        appsListScrollView.hasVerticalScroller = true
        appsListScrollView.drawsBackground = false

        let appsClipView = FlippedClipView()
        appsClipView.drawsBackground = false
        appsListScrollView.contentView = appsClipView
        appsListScrollView.documentView = appsListStack
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

    override func viewDidAppear() {
        super.viewDidAppear()
        if appearanceObservation == nil {
            appearanceObservation = view.observe(\.effectiveAppearance) { [weak self] _, _ in
                self?.updateCardColors()
            }
        }
    }

    private var appearanceObservation: NSKeyValueObservation?

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
            text = "\(startStr) \u{2013} \(endStr)"
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
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            let bg = NSColor.Semantic.backgroundSecondary
            timelineCard.layer?.backgroundColor = bg.cgColor
            appsCard.layer?.backgroundColor = bg.cgColor
            let border = NSColor.Semantic.borderSubtle
            toolbarBorder.layer?.backgroundColor = border.cgColor
            appsDivider.layer?.backgroundColor = border.cgColor
        }
    }

    // MARK: - Data Loading

    private func loadData(from: Date, to: Date) {
        do {
            appCache.removeAll()

            if deviceFilter == nil || deviceFilter == "this" {
                appSummaries = try db.fetchAppSummaries(from: from, to: to)
                localLogs = try db.fetchLogs(from: from, to: to)
                for log in localLogs where appCache[log.appId] == nil {
                    appCache[log.appId] = try db.fetchAppInfo(appId: log.appId)
                }
            } else {
                appSummaries = []
                localLogs = []
            }

            if deviceFilter == nil {
                remoteLogs = try db.fetchRemoteLogs(from: from, to: to)
            } else if deviceFilter != "this" {
                remoteLogs = try db.fetchRemoteLogs(from: from, to: to)
                    .filter { $0.deviceName == deviceFilter }
            } else {
                remoteLogs = []
            }

            allTags = try db.fetchAllTags()
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
                    colorIndex: GanttColorPalette.colorIndex(for: appName),
                    logIds: [log.id],
                    tagId: log.tagId
                ))
            }
        }

        if deviceFilter == nil || deviceFilter != "this" {
            for log in remoteLogs where !log.isIdle {
                entries.append(GanttEntry(
                    appName: log.appName,
                    startTime: log.startTime,
                    endTime: log.endTime,
                    colorIndex: GanttColorPalette.colorIndex(for: log.appName),
                    logIds: [],
                    tagId: nil
                ))
            }
        }

        let merged = mergeEntries(entries, threshold: groupingInterval)
        currentGanttEntries = merged
        ganttHostingView.rootView = SessionGanttView(
            entries: merged,
            selectionState: ganttSelection,
            tags: allTags
        )
    }

    private func mergeEntries(_ entries: [GanttEntry], threshold: TimeInterval) -> [GanttEntry] {
        let grouped = Dictionary(grouping: entries) { $0.appName }
        var result: [GanttEntry] = []

        for (_, appEntries) in grouped {
            let sorted = appEntries.sorted { $0.startTime < $1.startTime }
            var merged = [GanttEntry]()

            for entry in sorted {
                if let last = merged.last,
                   entry.startTime.timeIntervalSince(last.endTime) < threshold {
                    let combined = GanttEntry(
                        appName: last.appName,
                        startTime: last.startTime,
                        endTime: max(last.endTime, entry.endTime),
                        colorIndex: last.colorIndex,
                        logIds: last.logIds + entry.logIds,
                        tagId: last.tagId ?? entry.tagId
                    )
                    merged[merged.count - 1] = combined
                } else {
                    merged.append(entry)
                }
            }

            result.append(contentsOf: merged)
        }

        return result
    }

    // MARK: - Donut + Apps List

    private func updateDonutAndAppsList() {
        let totalDuration = appSummaries.reduce(0.0) { $0 + $1.totalDuration }

        // Donut chart
        let donutEntries = appSummaries.map { summary in
            DonutChartEntry(
                appName: summary.appName,
                duration: summary.totalDuration,
                color: GanttColorPalette.color(for: summary.appName),
                icon: summary.icon.map { Image(nsImage: $0) }
            )
        }
        donutHostingView.rootView = DonutChartView(entries: donutEntries)

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
        let activeDuration = appSummaries.reduce(0.0) { $0 + $1.totalDuration }
        let longestSession = (try? db.fetchLongestSession(from: from, to: to)) ?? 0
        let appsCount = appSummaries.count

        // Total time = wall-clock span from earliest to latest activity
        let allStarts: [Date] = localLogs.map(\.startTime) + remoteLogs.map(\.startTime)
        let allEnds: [Date] = localLogs.map(\.endTime) + remoteLogs.map(\.endTime)
        let wallClock: TimeInterval
        if let earliest = allStarts.min(), let latest = allEnds.max() {
            wallClock = latest.timeIntervalSince(earliest)
        } else {
            wallClock = activeDuration
        }

        metricsGrid.configure(with: MetricsGridView.Data(
            totalTime: formatDuration(wallClock),
            activeTime: formatDuration(activeDuration),
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

    // MARK: - Tag Selection

    @objc private func ganttRightClicked(_ gesture: NSClickGestureRecognizer) {
        guard ganttSelection.hasSelection else { return }
        let location = gesture.location(in: ganttHostingView)
        showTagPopover(relativeTo: location)
    }

    private func showTagPopover(relativeTo point: NSPoint) {
        tagPopover?.close()

        let selectedEntries = currentGanttEntries.filter { ganttSelection.selectedEntryIds.contains($0.id) }
        let logIds = selectedEntries.flatMap(\.logIds)
        guard !logIds.isEmpty else { return }

        let popoverView = TagPopoverView(tags: allTags) { [weak self] tagId in
            self?.tagPopover?.close()
            self?.tagPopover = nil
            self?.handleTagAssignment(logIds: logIds, tagId: tagId)
        }

        let hostingVC = NSHostingController(rootView: popoverView)
        let popover = NSPopover()
        popover.contentViewController = hostingVC
        popover.behavior = .transient

        let rect = NSRect(x: point.x, y: point.y, width: 1, height: 1)
        popover.show(relativeTo: rect, of: ganttHostingView, preferredEdge: .minY)
        tagPopover = popover
    }

    private func handleTagAssignment(logIds: [Int64], tagId: Int64?) {
        do {
            try db.setTagForLogs(logIds: logIds, tagId: tagId)
            ganttSelection.clear()
            reload()
        } catch {
            print("Error assigning tag: \(error)")
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            ganttSelection.clear()
        } else {
            super.keyDown(with: event)
        }
    }
}
