import Cocoa
import ServiceManagement

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var db: DatabaseManager!
    private var tracker: ActivityTracker!
    private var syncManager: SyncManager?
    private var timelineVC: TimelineViewController!
    private var detailWindow: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupDatabase()
        setupMenubar()
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
            button.action = #selector(togglePopover)
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
            syncManager?.onStatusChanged = { [weak self] (status: SyncManager.SyncStatus) in
                self?.timelineVC.updateSyncStatus(status)
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
            if let status = syncManager?.syncStatus {
                timelineVC.updateSyncStatus(status)
            }
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
}
