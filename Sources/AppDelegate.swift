import Cocoa
import ServiceManagement

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var db: DatabaseManager!
    private var tracker: ActivityTracker!
    private var syncManager: SyncManager?
    private var lastSyncSuccess: Bool?
    private var timelineVC: TimelineViewController!
    private var detailWindow: NSWindow?
    private var statusMenu: NSMenu!
    private var syncMenuItem: NSMenuItem!

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupDatabase()
        setupMenubar()
        setupStatusMenu()
        setupTracker()
        setupSync()
        registerAutoLaunch()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        tracker?.stop()
        syncManager?.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    private func setupDatabase() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("EmpTracking")
        let dbPath = dbDir.appendingPathComponent("tracking.db").path

        db = DatabaseManager(path: dbPath)
        do {
            try db.initialize()
        } catch {
            print("Failed to initialize database: \(error)")
        }
    }

    private func setupMenubar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "EmpTracking")
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        timelineVC = TimelineViewController(db: db)
        timelineVC.onDetail = { [weak self] in
            self?.showDetailWindow()
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 500)
        popover.behavior = .transient
        popover.contentViewController = timelineVC
    }

    private func setupTracker() {
        let idleMonitor = IdleStateMonitor()
        tracker = ActivityTracker(db: db, idleMonitor: idleMonitor)
        tracker.onUpdate = { [weak self] in
            if self?.popover.isShown == true {
                self?.timelineVC.reload()
            }
        }
        tracker.start()
    }

    private func setupSync() {
        do {
            syncManager = try SyncManager(db: db)
            syncManager?.onSyncCompleted = { [weak self] in
                if self?.popover.isShown == true {
                    self?.timelineVC.reload()
                }
            }
            syncManager?.onStatusChanged = { [weak self] status in
                switch status {
                case .synced:
                    self?.lastSyncSuccess = true
                case .error:
                    self?.lastSyncSuccess = false
                case .pending(let count) where count > 0:
                    self?.lastSyncSuccess = false
                default:
                    break
                }
            }
            syncManager?.start()
        } catch {
            print("Failed to start sync: \(error)")
        }
    }

    private func registerAutoLaunch() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            print("Failed to register login item: \(error)")
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            timelineVC.reload()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showDetailWindow() {
        popover.performClose(nil)

        if let window = detailWindow {
            (window.contentViewController as? DetailViewController)?.reload()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let deviceId = (try? db.getOrCreateDeviceId()) ?? ""
        let detailVC = DetailViewController(db: db, deviceId: deviceId)
        let window = NSWindow(contentViewController: detailVC)
        window.title = "Подробнее"
        window.setContentSize(NSSize(width: 500, height: 600))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.minSize = NSSize(width: 400, height: 300)
        window.center()
        window.isReleasedWhenClosed = false
        self.detailWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: - Status Menu (Right-Click)

    private func setupStatusMenu() {
        statusMenu = NSMenu()

        let detailItem = NSMenuItem(title: "Подробно", action: #selector(showDetailFromMenu), keyEquivalent: "")
        detailItem.target = self
        statusMenu.addItem(detailItem)

        syncMenuItem = NSMenuItem(title: "Синхронизация — никогда", action: #selector(syncFromMenu), keyEquivalent: "")
        syncMenuItem.target = self
        statusMenu.addItem(syncMenuItem)

        statusMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusMenu.addItem(quitItem)
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            updateSyncMenuTitle()
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            DispatchQueue.main.async { [weak self] in
                self?.statusItem.menu = nil
            }
        } else {
            togglePopover()
        }
    }

    private func updateSyncMenuTitle() {
        let prefix: String
        switch lastSyncSuccess {
        case .some(true): prefix = "✅ "
        case .some(false): prefix = "❌ "
        case .none: prefix = ""
        }

        let lastPullTime = try? db.fetchSetting(key: "last_pull_time")
        if let timeStr = lastPullTime, let timestamp = TimeInterval(timeStr) {
            let date = Date(timeIntervalSince1970: timestamp)
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            syncMenuItem.title = "\(prefix)Синхронизация — \(formatter.string(from: date))"
        } else {
            syncMenuItem.title = "\(prefix)Синхронизация — никогда"
        }
    }

    @objc private func showDetailFromMenu() {
        showDetailWindow()
    }

    @objc private func syncFromMenu() {
        syncManager?.syncNow()
    }
}
