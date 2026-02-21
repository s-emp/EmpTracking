import Cocoa

final class DetailViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
    private let db: DatabaseManager
    private let deviceId: String
    private var logs: [ActivityLog] = []
    private var filteredLogs: [ActivityLog] = []
    private var remoteLogs: [RemoteLog] = []
    private var filteredRemoteLogs: [RemoteLog] = []
    private var tagSummaries: [TagSummary] = []
    private var appCache: [Int64: AppInfo] = [:]
    private var tagCache: [Int64: Tag] = [:]

    /// Unified row for the table when mixing local and remote logs.
    private enum TableRow {
        case local(ActivityLog)
        case remote(RemoteLog)

        var startTime: Date {
            switch self {
            case .local(let log): return log.startTime
            case .remote(let log): return log.startTime
            }
        }

        var isIdle: Bool {
            switch self {
            case .local(let log): return log.isIdle
            case .remote(let log): return log.isIdle
            }
        }

        var duration: TimeInterval {
            switch self {
            case .local(let log): return log.endTime.timeIntervalSince(log.startTime)
            case .remote(let log): return log.endTime.timeIntervalSince(log.startTime)
            }
        }
    }
    private var mergedRows: [TableRow] = []

    private enum TableMode: Int { case apps = 0, tags = 1 }
    private var tableMode: TableMode = .apps

    private enum TimelineMode: Int { case day = 0, week = 1, month = 2 }
    private var timelineMode: TimelineMode = .day

    private enum DeviceFilter: Int { case all = 0, thisMac = 1, others = 2 }
    private var deviceFilter: DeviceFilter = .thisMac

    private var anchorDate = Date()
    private var selectedSlot: Int? = nil

    // Timeline data
    private var hourlyData: [Int: [TagSlotDuration]] = [:]
    private var dailyData: [Date: [TagSlotDuration]] = [:]
    private var slotDates: [Date] = []

    // Formatters
    private let weekDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EE"
        return f
    }()

    // UI elements
    private let dateLabel = NSTextField(labelWithString: "")
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let calendarButton = NSButton()
    private let timelineModeControl = NSSegmentedControl()
    private let timelineHeaderLabel = NSTextField(labelWithString: "")
    private let timelineBackgroundView = NSView()
    private let timelineCollectionView = NSCollectionView()
    private let timelineScrollView = NSScrollView()
    private let deviceFilterControl = NSSegmentedControl()
    private let tableModeControl = NSSegmentedControl()
    private let totalLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var calendarPopover: NSPopover?

    init(db: DatabaseManager, deviceId: String = "") {
        self.db = db
        self.deviceId = deviceId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 700))
        self.view = container

        // Navigation row
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        dateLabel.lineBreakMode = .byTruncatingTail
        dateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        container.addSubview(dateLabel)

        prevButton.translatesAutoresizingMaskIntoConstraints = false
        prevButton.bezelStyle = .inline
        prevButton.title = "\u{2039}"
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
        nextButton.title = "\u{203A}"
        nextButton.font = .systemFont(ofSize: 16, weight: .medium)
        nextButton.target = self
        nextButton.action = #selector(nextTapped)
        container.addSubview(nextButton)

        timelineModeControl.translatesAutoresizingMaskIntoConstraints = false
        timelineModeControl.segmentCount = 3
        timelineModeControl.setLabel("\u{0414}\u{0435}\u{043D}\u{044C}", forSegment: 0)
        timelineModeControl.setLabel("\u{041D}\u{0435}\u{0434}\u{0435}\u{043B}\u{044F}", forSegment: 1)
        timelineModeControl.setLabel("\u{041C}\u{0435}\u{0441}\u{044F}\u{0446}", forSegment: 2)
        timelineModeControl.selectedSegment = 0
        timelineModeControl.target = self
        timelineModeControl.action = #selector(timelineModeChanged(_:))
        timelineModeControl.segmentStyle = .rounded
        container.addSubview(timelineModeControl)

        // Timeline header
        timelineHeaderLabel.translatesAutoresizingMaskIntoConstraints = false
        timelineHeaderLabel.attributedStringValue = NSAttributedString(
            string: "TIMELINE",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
                .kern: 1.5,
            ]
        )
        container.addSubview(timelineHeaderLabel)

        // Timeline background
        timelineBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        timelineBackgroundView.wantsLayer = true
        timelineBackgroundView.layer?.cornerRadius = 8
        updateTimelineBackgroundColor()
        container.addSubview(timelineBackgroundView)

        // Timeline collection
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

        // Device filter control
        deviceFilterControl.translatesAutoresizingMaskIntoConstraints = false
        deviceFilterControl.segmentCount = 3
        deviceFilterControl.setLabel("\u{0412}\u{0441}\u{0435}", forSegment: 0)
        deviceFilterControl.setLabel("\u{042D}\u{0442}\u{043E}\u{0442} Mac", forSegment: 1)
        deviceFilterControl.setLabel("\u{0414}\u{0440}\u{0443}\u{0433}\u{0438}\u{0435}", forSegment: 2)
        deviceFilterControl.selectedSegment = 1
        deviceFilterControl.target = self
        deviceFilterControl.action = #selector(deviceFilterChanged(_:))
        deviceFilterControl.segmentStyle = .rounded
        container.addSubview(deviceFilterControl)

        // Table mode controls
        tableModeControl.translatesAutoresizingMaskIntoConstraints = false
        tableModeControl.segmentCount = 2
        tableModeControl.setLabel("\u{041F}\u{0440}\u{0438}\u{043B}\u{043E}\u{0436}\u{0435}\u{043D}\u{0438}\u{044F}", forSegment: 0)
        tableModeControl.setLabel("\u{0422}\u{0435}\u{0433}\u{0438}", forSegment: 1)
        tableModeControl.selectedSegment = 0
        tableModeControl.target = self
        tableModeControl.action = #selector(tableModeChanged(_:))
        tableModeControl.segmentStyle = .rounded
        container.addSubview(tableModeControl)

        totalLabel.translatesAutoresizingMaskIntoConstraints = false
        totalLabel.font = .systemFont(ofSize: 12)
        totalLabel.textColor = .secondaryLabelColor
        container.addSubview(totalLabel)

        // Session table
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

            timelineHeaderLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 12),
            timelineHeaderLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),

            timelineBackgroundView.topAnchor.constraint(equalTo: timelineHeaderLabel.bottomAnchor, constant: 4),
            timelineBackgroundView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            timelineBackgroundView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),

            timelineScrollView.topAnchor.constraint(equalTo: timelineBackgroundView.topAnchor, constant: 4),
            timelineScrollView.leadingAnchor.constraint(equalTo: timelineBackgroundView.leadingAnchor, constant: 4),
            timelineScrollView.trailingAnchor.constraint(equalTo: timelineBackgroundView.trailingAnchor, constant: -4),
            timelineScrollView.heightAnchor.constraint(equalToConstant: timelineHeight),

            timelineBackgroundView.bottomAnchor.constraint(equalTo: timelineScrollView.bottomAnchor, constant: 4),

            deviceFilterControl.topAnchor.constraint(equalTo: timelineBackgroundView.bottomAnchor, constant: 8),
            deviceFilterControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),

            tableModeControl.topAnchor.constraint(equalTo: deviceFilterControl.bottomAnchor, constant: 8),
            tableModeControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),

            totalLabel.centerYAnchor.constraint(equalTo: tableModeControl.centerYAnchor),
            totalLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: tableModeControl.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
    }

    // MARK: - Navigation Actions

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
        calendarPopover = popover

        picker.target = self
        picker.action = #selector(calendarDatePicked(_:))
    }

    @objc private func calendarDatePicked(_ sender: NSDatePicker) {
        anchorDate = sender.dateValue
        selectedSlot = nil
        calendarPopover?.close()
        calendarPopover = nil
        reload()
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

    @objc private func deviceFilterChanged(_ sender: NSSegmentedControl) {
        deviceFilter = DeviceFilter(rawValue: sender.selectedSegment) ?? .thisMac
        reloadTable()
    }

    // MARK: - Data Loading

    func reload() {
        updateDateLabel()
        loadTimelineData()
        timelineCollectionView.reloadData()
        reloadTable()
    }

    private func updateDateLabel() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")

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
            dateLabel.stringValue = "\(startStr) \u{2013} \(endStr)"
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
                // Load local logs when filter is .all or .thisMac
                if deviceFilter == .all || deviceFilter == .thisMac {
                    logs = try db.fetchLogs(from: rangeStart, to: rangeEnd)
                    for log in logs where appCache[log.appId] == nil {
                        appCache[log.appId] = try db.fetchAppInfo(appId: log.appId)
                    }
                } else {
                    logs = []
                }

                // Load remote logs when filter is .all or .others
                if deviceFilter == .all || deviceFilter == .others {
                    remoteLogs = try db.fetchRemoteLogs(from: rangeStart, to: rangeEnd)
                } else {
                    remoteLogs = []
                }

                applySlotFilter()
                buildMergedRows()
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
            filteredRemoteLogs = remoteLogs
            return
        }
        let cal = Calendar.current
        switch timelineMode {
        case .day:
            filteredLogs = logs.filter { cal.component(.hour, from: $0.startTime) == slot }
            filteredRemoteLogs = remoteLogs.filter { cal.component(.hour, from: $0.startTime) == slot }
        case .week, .month:
            guard slot < slotDates.count else {
                filteredLogs = logs
                filteredRemoteLogs = remoteLogs
                return
            }
            let dayStart = slotDates[slot]
            let dayEnd = dayStart.addingTimeInterval(86400)
            filteredLogs = logs.filter { $0.startTime >= dayStart && $0.startTime < dayEnd }
            filteredRemoteLogs = remoteLogs.filter { $0.startTime >= dayStart && $0.startTime < dayEnd }
        }
    }

    private func buildMergedRows() {
        var rows: [TableRow] = []
        rows.append(contentsOf: filteredLogs.map { .local($0) })
        rows.append(contentsOf: filteredRemoteLogs.map { .remote($0) })
        rows.sort { $0.startTime > $1.startTime }
        mergedRows = rows
    }

    private func reloadTable() {
        loadTableData()
        let active: TimeInterval
        switch tableMode {
        case .apps:
            active = mergedRows.filter { !$0.isIdle }.reduce(0.0) { $0 + $1.duration }
        case .tags:
            active = tagSummaries.reduce(0.0) { $0 + $1.totalDuration }
        }
        let hours = Int(active) / 3600
        let minutes = (Int(active) % 3600) / 60
        totalLabel.stringValue = "\u{0410}\u{043A}\u{0442}\u{0438}\u{0432}\u{043D}\u{043E}: \(hours)\u{0447} \(minutes)\u{043C}\u{0438}\u{043D}"
        tableView.reloadData()
    }

    // MARK: - Date Helpers

    private func weekRange(for date: Date) -> (Date, Date) {
        let cal = Calendar.current
        var start = cal.startOfDay(for: date)
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
            label = slot < slotDates.count ? weekDayFormatter.string(from: slotDates[slot]) : ""
            slotData = slot < slotDates.count ? (dailyData[slotDates[slot]] ?? []) : []
            maxDuration = 86400
        case .month:
            let cal = Calendar.current
            label = slot < slotDates.count ? "\(cal.component(.day, from: slotDates[slot]))" : ""
            slotData = slot < slotDates.count ? (dailyData[slotDates[slot]] ?? []) : []
            maxDuration = 86400
        }

        let totalActive = slotData.reduce(0.0) { $0 + $1.duration }
        let fillFraction = totalActive > 0 ? min(totalActive / maxDuration, 1.0) : 0

        let segments: [(color: NSColor, fraction: CGFloat)] = slotData.map { entry in
            let color: NSColor
            if let tagId = entry.tagId, let tag = tagCache[tagId] {
                color = NSColor(hex: isDark ? tag.colorDark : tag.colorLight)
            } else {
                color = .systemGray
            }
            let fraction = totalActive > 0 ? CGFloat(fillFraction * (entry.duration / totalActive)) : 0
            return (color, fraction)
        }

        cell.configure(label: label, segments: segments)
        cell.isHighlighted = (selectedSlot == slot)

        let totalItems: Int
        switch timelineMode {
        case .day: totalItems = 24
        case .week: totalItems = 7
        case .month: totalItems = slotDates.count
        }
        cell.showSeparator = slot < totalItems - 1

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
        let width = count > 0 ? max(collectionView.bounds.width / count, 14) : 14
        return NSSize(width: width, height: collectionView.bounds.height)
    }

    // MARK: - NSTableViewDataSource

    nonisolated func numberOfRows(in tableView: NSTableView) -> Int {
        MainActor.assumeIsolated {
            switch tableMode {
            case .apps: return mergedRows.count
            case .tags: return tagSummaries.count
            }
        }
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch tableMode {
        case .apps:
            let id = NSUserInterfaceItemIdentifier("DetailCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? DetailCellView)
                ?? DetailCellView()
            cell.identifier = id

            let tableRow = mergedRows[row]
            switch tableRow {
            case .local(let log):
                let appInfo = appCache[log.appId]
                let resolvedTag = resolveTag(log: log, appInfo: appInfo)
                cell.configure(log: log, appInfo: appInfo, tag: resolvedTag)
            case .remote(let log):
                cell.configure(remoteLog: log)
            }
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
        guard tableMode == .apps else { return false }
        let tableRow = mergedRows[row]
        guard case .local(let log) = tableRow, !log.isIdle else { return false }
        showSessionTagMenu(forLog: log, at: row)
        return false
    }

    // MARK: - Theme support

    private var appearanceObservation: NSKeyValueObservation?

    override func viewDidAppear() {
        super.viewDidAppear()
        if appearanceObservation == nil {
            appearanceObservation = view.observe(\.effectiveAppearance) { [weak self] _, _ in
                self?.timelineCollectionView.reloadData()
                self?.updateTimelineBackgroundColor()
            }
        }
    }

    private func updateTimelineBackgroundColor() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        timelineBackgroundView.layer?.backgroundColor = isDark
            ? NSColor(white: 0.15, alpha: 1.0).cgColor
            : NSColor(white: 0.95, alpha: 1.0).cgColor
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
        do {
            tags = try db.fetchAllTags()
        } catch {
            print("Error loading tags: \(error)")
            return
        }

        let isOverridden = log.tagId != nil

        // "App tag" item -- reset to app default
        let appTagItem = NSMenuItem(title: "\u{0422}\u{0435}\u{0433} \u{043F}\u{0440}\u{0438}\u{043B}\u{043E}\u{0436}\u{0435}\u{043D}\u{0438}\u{044F}", action: #selector(sessionTagMenuClicked(_:)), keyEquivalent: "")
        appTagItem.target = self
        appTagItem.representedObject = ["logId": log.id, "action": "reset"] as NSDictionary
        if !isOverridden { appTagItem.state = .on }
        menu.addItem(appTagItem)

        // "No tag" -- explicitly remove
        let noTagItem = NSMenuItem(title: "\u{0411}\u{0435}\u{0437} \u{0442}\u{0435}\u{0433}\u{0430}", action: #selector(sessionTagMenuClicked(_:)), keyEquivalent: "")
        noTagItem.target = self
        noTagItem.representedObject = ["logId": log.id, "action": "none"] as NSDictionary
        menu.addItem(noTagItem)

        if !tags.isEmpty {
            menu.addItem(.separator())
        }

        for tag in tags {
            let item = NSMenuItem(title: tag.name, action: #selector(sessionTagMenuClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["logId": log.id, "tagId": tag.id] as NSDictionary
            if log.tagId == tag.id { item.state = .on }

            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let color = NSColor(hex: isDark ? tag.colorDark : tag.colorLight)
            let dot = NSAttributedString(string: "\u{25CF} ", attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 13)])
            let name = NSAttributedString(string: tag.name, attributes: [.font: NSFont.systemFont(ofSize: 13)])
            let title = NSMutableAttributedString()
            title.append(dot)
            title.append(name)
            item.attributedTitle = title

            menu.addItem(item)
        }

        menu.addItem(.separator())

        let createItem = NSMenuItem(title: "\u{0421}\u{043E}\u{0437}\u{0434}\u{0430}\u{0442}\u{044C} \u{0442}\u{0435}\u{0433}...", action: #selector(createTagFromDetail(_:)), keyEquivalent: "")
        createItem.target = self
        menu.addItem(createItem)

        let rect = tableView.rect(ofRow: row)
        menu.popUp(positioning: nil, at: NSPoint(x: rect.midX, y: rect.midY), in: tableView)
    }

    @objc private func sessionTagMenuClicked(_ sender: NSMenuItem) {
        guard let dict = sender.representedObject as? NSDictionary,
              let logId = dict["logId"] as? Int64 else { return }

        do {
            if let _ = dict["action"] as? String {
                // "reset" or "none" -- both set tagId to nil
                try db.setSessionTag(logId: logId, tagId: nil)
            } else if let tagId = dict["tagId"] as? Int64 {
                try db.setSessionTag(logId: logId, tagId: tagId)
            }
            reload()
        } catch {
            print("Error setting session tag: \(error)")
        }
    }

    @objc private func createTagFromDetail(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "\u{0421}\u{043E}\u{0437}\u{0434}\u{0430}\u{0442}\u{044C} \u{0442}\u{0435}\u{0433}"
        alert.addButton(withTitle: "\u{0421}\u{043E}\u{0437}\u{0434}\u{0430}\u{0442}\u{044C}")
        alert.addButton(withTitle: "\u{041E}\u{0442}\u{043C}\u{0435}\u{043D}\u{0430}")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))

        let nameField = NSTextField(frame: NSRect(x: 0, y: 70, width: 300, height: 24))
        nameField.placeholderString = "\u{041D}\u{0430}\u{0437}\u{0432}\u{0430}\u{043D}\u{0438}\u{0435} \u{0442}\u{0435}\u{0433}\u{0430}"
        container.addSubview(nameField)

        let lightLabel = NSTextField(labelWithString: "\u{0421}\u{0432}\u{0435}\u{0442}\u{043B}\u{0430}\u{044F}:")
        lightLabel.frame = NSRect(x: 0, y: 35, width: 60, height: 20)
        container.addSubview(lightLabel)

        let lightColorWell = NSColorWell(frame: NSRect(x: 65, y: 30, width: 50, height: 30))
        lightColorWell.color = .systemGreen
        container.addSubview(lightColorWell)

        let darkLabel = NSTextField(labelWithString: "\u{0422}\u{0451}\u{043C}\u{043D}\u{0430}\u{044F}:")
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
            errorAlert.messageText = "\u{041E}\u{0448}\u{0438}\u{0431}\u{043A}\u{0430}"
            errorAlert.informativeText = "\u{0422}\u{0435}\u{0433} \u{0441} \u{0442}\u{0430}\u{043A}\u{0438}\u{043C} \u{0438}\u{043C}\u{0435}\u{043D}\u{0435}\u{043C} \u{0443}\u{0436}\u{0435} \u{0441}\u{0443}\u{0449}\u{0435}\u{0441}\u{0442}\u{0432}\u{0443}\u{0435}\u{0442}."
            errorAlert.runModal()
        }
    }
}
