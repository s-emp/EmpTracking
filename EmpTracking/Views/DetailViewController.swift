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
            // Always cache tags
            let allTags = try db.fetchAllTags()
            tagCache = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })

            switch mode {
            case .apps:
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
        do {
            tags = try db.fetchAllTags()
        } catch {
            print("Error loading tags: \(error)")
            return
        }

        let isOverridden = log.tagId != nil

        // "App tag" item — reset to app default
        let appTagItem = NSMenuItem(title: "Тег приложения", action: #selector(sessionTagMenuClicked(_:)), keyEquivalent: "")
        appTagItem.target = self
        appTagItem.representedObject = ["logId": log.id, "action": "reset"] as NSDictionary
        if !isOverridden { appTagItem.state = .on }
        menu.addItem(appTagItem)

        // "No tag" — explicitly remove
        let noTagItem = NSMenuItem(title: "Без тега", action: #selector(sessionTagMenuClicked(_:)), keyEquivalent: "")
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
        guard let dict = sender.representedObject as? NSDictionary,
              let logId = dict["logId"] as? Int64 else { return }

        do {
            if let _ = dict["action"] as? String {
                // "reset" or "none" — both set tagId to nil
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
