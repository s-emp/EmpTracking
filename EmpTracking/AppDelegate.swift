import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var db: DatabaseManager!
    private var tracker: ActivityTracker!
    private var timelineVC: TimelineViewController!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.windows.forEach { $0.close() }

        setupDatabase()
        setupMenubar()
        setupTracker()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        tracker?.stop()
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
            button.action = #selector(togglePopover)
        }

        timelineVC = TimelineViewController(db: db)

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

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            timelineVC.reload()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
