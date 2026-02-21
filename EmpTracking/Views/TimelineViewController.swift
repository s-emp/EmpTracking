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
    private let syncButton = NSButton(title: "Синхронизация", target: nil, action: nil)

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

        syncButton.translatesAutoresizingMaskIntoConstraints = false
        syncButton.bezelStyle = .inline
        syncButton.font = .systemFont(ofSize: 11)
        syncButton.isEnabled = false
        container.addSubview(syncButton)

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

            syncButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            syncButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),

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

    func updateSyncStatus(_ status: SyncManager.SyncStatus) {
        switch status {
        case .synced:
            syncButton.title = "Синхронизация \u{2713}"
            syncButton.contentTintColor = .systemGreen
        case .syncing:
            syncButton.title = "Синхронизация..."
            syncButton.contentTintColor = .secondaryLabelColor
        case .pending(let count):
            syncButton.title = "Не синхр: \(count)"
            syncButton.contentTintColor = .systemOrange
        case .error:
            syncButton.title = "Синхр. ошибка"
            syncButton.contentTintColor = .systemRed
        case .idle:
            syncButton.title = "Синхронизация"
            syncButton.contentTintColor = .secondaryLabelColor
        }
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

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard mode == .apps else { return false }
        let summary = appSummaries[row]
        showTagMenu(forAppId: summary.appId, at: row)
        return false
    }

    // MARK: - Tag Menu

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
        noTagItem.representedObject = ["appId": appId, "tagId": NSNull()] as NSDictionary
        if currentTagId == nil { noTagItem.state = .on }
        menu.addItem(noTagItem)

        if !tags.isEmpty {
            menu.addItem(.separator())
        }

        for tag in tags {
            let item = NSMenuItem(title: tag.name, action: #selector(tagMenuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["appId": appId, "tagId": tag.id] as NSDictionary
            if currentTagId == tag.id { item.state = .on }

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

        let createItem = NSMenuItem(title: "Создать тег...", action: #selector(createTagClicked(_:)), keyEquivalent: "")
        createItem.target = self
        menu.addItem(createItem)

        let rect = tableView.rect(ofRow: row)
        menu.popUp(positioning: nil, at: NSPoint(x: rect.midX, y: rect.midY), in: tableView)
    }

    @objc private func tagMenuItemClicked(_ sender: NSMenuItem) {
        guard let dict = sender.representedObject as? NSDictionary,
              let appId = dict["appId"] as? Int64 else { return }
        let tagId = dict["tagId"] as? Int64 // NSNull becomes nil
        do {
            try db.setDefaultTag(appId: appId, tagId: tagId)
            reload()
        } catch {
            print("Error setting tag: \(error)")
        }
    }

    @objc private func createTagClicked(_ sender: NSMenuItem) {
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
