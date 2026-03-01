import Cocoa
import EmpUI_macOS

final class TimelineViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let db: DatabaseManager
    private var appSummaries: [AppSummary] = []
    private var totalDuration: TimeInterval = 0
    var onDetail: (() -> Void)?

    // MARK: - UI Elements

    private let dateLabel = EmpText()
    private let totalLabel = EmpText()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let showMoreButton = EmpButton()

    // MARK: - Init

    init(db: DatabaseManager) {
        self.db = db
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Load View

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        self.view = container

        let horizontalPadding = EmpSpacing.m.rawValue   // 16
        let topPadding = EmpSpacing.m.rawValue           // 16
        let sectionGap = EmpSpacing.s.rawValue           // 12
        let smallGap = EmpSpacing.xs.rawValue             // 8

        // Date label (left)
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(dateLabel)

        // Total time label (right)
        totalLabel.translatesAutoresizingMaskIntoConstraints = false
        totalLabel.setContentHuggingPriority(.required, for: .horizontal)
        totalLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        container.addSubview(totalLabel)

        // Table view
        let column = NSTableColumn(identifier: .init("activity"))
        column.title = ""
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 44
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .none
        tableView.style = .plain

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        tableView.backgroundColor = .clear
        container.addSubview(scrollView)

        // "Show more..." button (ghost, small, centered)
        showMoreButton.translatesAutoresizingMaskIntoConstraints = false
        showMoreButton.configure(with: EmpButton.Preset.ghost(
            .primary,
            content: .init(center: .text("Show more...")),
            size: .small
        ))
        showMoreButton.action = { [weak self] in
            self?.onDetail?()
        }
        container.addSubview(showMoreButton)

        NSLayoutConstraint.activate([
            // Date label — top-left
            dateLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: topPadding),
            dateLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalPadding),

            // Total label — top-right, vertically centered with date
            totalLabel.centerYAnchor.constraint(equalTo: dateLabel.centerYAnchor),
            totalLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalPadding),
            totalLabel.leadingAnchor.constraint(greaterThanOrEqualTo: dateLabel.trailingAnchor, constant: smallGap),

            // Scroll view — below header, above button
            scrollView.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: sectionGap),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: showMoreButton.topAnchor, constant: -smallGap),

            // "Show more..." button — centered at bottom
            showMoreButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            showMoreButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -sectionGap),
        ])
    }

    // MARK: - Lifecycle

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
    }

    // MARK: - Reload

    func reload() {
        // Date header — English, "MMMM d" format
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM d"

        dateLabel.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: formatter.string(from: Date()),
                font: .systemFont(ofSize: 14),
                color: NSColor.Semantic.textSecondary
            )),
            numberOfLines: 1
        ))

        // Fetch app summaries
        let since = Calendar.current.startOfDay(for: Date())

        do {
            appSummaries = try db.fetchAppSummaries(since: since)
            totalDuration = appSummaries.reduce(0.0) { $0 + $1.totalDuration }
        } catch {
            print("Error fetching summaries: \(error)")
            appSummaries = []
            totalDuration = 0
        }

        // Total time header
        totalLabel.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: formatDuration(totalDuration),
                font: .systemFont(ofSize: 16, weight: .bold),
                color: NSColor.Semantic.textPrimary
            )),
            numberOfLines: 1,
            alignment: .right
        ))

        tableView.reloadData()
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)min"
        } else {
            return "\(minutes)min"
        }
    }

    // MARK: - NSTableViewDataSource

    nonisolated func numberOfRows(in tableView: NSTableView) -> Int {
        MainActor.assumeIsolated {
            return appSummaries.count
        }
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("TimelineCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? TimelineCellView)
            ?? TimelineCellView()
        cell.identifier = id
        cell.configure(summary: appSummaries[row], totalDuration: totalDuration)
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return false
    }
}
