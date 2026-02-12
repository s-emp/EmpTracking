import Cocoa

final class DetailViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let db: DatabaseManager
    private var logs: [ActivityLog] = []
    private var appCache: [Int64: AppInfo] = [:]

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

            scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
    }

    func reload() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        headerLabel.stringValue = formatter.string(from: Date())

        do {
            logs = try db.fetchTodayLogs()

            for log in logs where appCache[log.appId] == nil {
                appCache[log.appId] = try db.fetchAppInfo(appId: log.appId)
            }

            let totalActive = logs.filter { !$0.isIdle }.reduce(0.0) {
                $0 + $1.endTime.timeIntervalSince($1.startTime)
            }
            let hours = Int(totalActive) / 3600
            let minutes = (Int(totalActive) % 3600) / 60
            totalLabel.stringValue = "Активно: \(hours)ч \(minutes)мин"
        } catch {
            print("Error fetching detail logs: \(error)")
        }

        tableView.reloadData()
    }

    // MARK: - NSTableViewDataSource

    nonisolated func numberOfRows(in tableView: NSTableView) -> Int {
        MainActor.assumeIsolated {
            logs.count
        }
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("DetailCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? DetailCellView)
            ?? DetailCellView()
        cell.identifier = id

        let log = logs[row]
        let appInfo = appCache[log.appId]
        cell.configure(log: log, appInfo: appInfo)

        return cell
    }
}
