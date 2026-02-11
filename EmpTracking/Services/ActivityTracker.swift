import Cocoa
import ApplicationServices

final class ActivityTracker {
    private let db: DatabaseManager
    private let idleMonitor: IdleStateMonitor
    private var timer: Timer?
    private var currentLogId: Int64?
    private var currentBundleId: String?
    private var currentWindowTitle: String?
    private var isCurrentlyIdle = false

    var onUpdate: (() -> Void)?

    init(db: DatabaseManager, idleMonitor: IdleStateMonitor) {
        self.db = db
        self.idleMonitor = idleMonitor

        idleMonitor.onAwayStateChanged = { [weak self] away in
            if away {
                self?.finalizeCurrentLog()
            }
        }
    }

    func start() {
        requestAccessibilityIfNeeded()
        idleMonitor.start()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        idleMonitor.stop()
    }

    private func tick() {
        guard !idleMonitor.isUserAway else { return }

        let isIdle = idleMonitor.isUserIdle()

        if isIdle {
            if !isCurrentlyIdle {
                finalizeCurrentLog()
                isCurrentlyIdle = true
                startNewLog(appName: "Idle", bundleId: "com.emptracking.idle", windowTitle: nil, isIdle: true, icon: nil)
            } else {
                updateCurrentLogEndTime()
            }
            return
        }

        if isCurrentlyIdle {
            finalizeCurrentLog()
            isCurrentlyIdle = false
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier,
              let appName = frontApp.localizedName else { return }

        let windowTitle = getWindowTitle(for: frontApp)

        if bundleId == currentBundleId && windowTitle == currentWindowTitle {
            updateCurrentLogEndTime()
        } else {
            finalizeCurrentLog()
            let iconData = frontApp.icon.flatMap { iconToData($0) }
            startNewLog(appName: appName, bundleId: bundleId, windowTitle: windowTitle, isIdle: false, icon: iconData)
        }
    }

    private func startNewLog(appName: String, bundleId: String, windowTitle: String?, isIdle: Bool, icon: Data?) {
        do {
            let appId = try db.insertOrGetApp(bundleId: bundleId, appName: appName, iconPNG: icon)
            let now = Date()
            let logId = try db.insertActivityLog(appId: appId, windowTitle: windowTitle, startTime: now, endTime: now, isIdle: isIdle)
            currentLogId = logId
            currentBundleId = bundleId
            currentWindowTitle = windowTitle
            onUpdate?()
        } catch {
            print("Error starting log: \(error)")
        }
    }

    private func updateCurrentLogEndTime() {
        guard let logId = currentLogId else { return }
        do {
            try db.updateEndTime(logId: logId, endTime: Date())
        } catch {
            print("Error updating log: \(error)")
        }
    }

    private func finalizeCurrentLog() {
        updateCurrentLogEndTime()
        currentLogId = nil
        currentBundleId = nil
        currentWindowTitle = nil
    }

    private func getWindowTitle(for app: NSRunningApplication) -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: AnyObject?
        let windowResult = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &windowValue
        )
        guard windowResult == .success else { return nil }

        var titleValue: AnyObject?
        let titleResult = AXUIElementCopyAttributeValue(
            windowValue as! AXUIElement, kAXTitleAttribute as CFString, &titleValue
        )
        guard titleResult == .success else { return nil }

        return titleValue as? String
    }

    private func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func iconToData(_ icon: NSImage) -> Data? {
        let size = NSSize(width: 32, height: 32)
        let resized = NSImage(size: size)
        resized.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: size))
        resized.unlockFocus()

        guard let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData
    }
}
