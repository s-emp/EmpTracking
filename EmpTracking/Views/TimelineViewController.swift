import Cocoa

final class TimelineViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let db: DatabaseManager
    private var summaries: [AppSummary] = []
    var onDetail: (() -> Void)?

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
        segmentedControl.segmentCount = 3
        segmentedControl.setLabel("День", forSegment: 0)
        segmentedControl.setLabel("Неделя", forSegment: 1)
        segmentedControl.setLabel("Месяц", forSegment: 2)
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
        reload()
    }

    @objc private func detailTapped() {
        onDetail?()
    }

    func reload() {
        let calendar = Calendar.current
        let now = Date()

        let since: Date
        switch segmentedControl.selectedSegment {
        case 1:
            since = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? calendar.startOfDay(for: now)
        case 2:
            since = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? calendar.startOfDay(for: now)
        default:
            since = calendar.startOfDay(for: now)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        switch segmentedControl.selectedSegment {
        case 1:
            formatter.dateFormat = "'Неделя' d MMM"
        case 2:
            formatter.dateFormat = "LLLL yyyy"
        default:
            formatter.dateFormat = "d MMMM yyyy"
        }
        headerLabel.stringValue = formatter.string(from: now)

        do {
            summaries = try db.fetchAppSummaries(since: since)

            let totalActive = summaries.reduce(0.0) { $0 + $1.totalDuration }
            let hours = Int(totalActive) / 3600
            let minutes = (Int(totalActive) % 3600) / 60
            totalLabel.stringValue = "\(hours)ч \(minutes)мин"
        } catch {
            print("Error fetching summaries: \(error)")
        }

        tableView.reloadData()
    }

    // MARK: - NSTableViewDataSource

    nonisolated func numberOfRows(in tableView: NSTableView) -> Int {
        MainActor.assumeIsolated {
            summaries.count
        }
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("TimelineCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? TimelineCellView)
            ?? TimelineCellView()
        cell.identifier = id

        let summary = summaries[row]
        cell.configure(summary: summary)

        return cell
    }
}
