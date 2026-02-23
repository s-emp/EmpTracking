import Cocoa
import CoreGraphics

final class IdleStateMonitor {
    private(set) var isUserAway = false
    private var observers: [Any] = []

    var onAwayStateChanged: ((Bool) -> Void)?

    private static let idleThreshold: TimeInterval = 120

    func start() {
        let wsnc = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()

        observers.append(wsnc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in self?.setAway(true) })

        observers.append(wsnc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.setAway(false) })

        observers.append(wsnc.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main) { [weak self] _ in self?.setAway(true) })

        observers.append(wsnc.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.setAway(false) })

        observers.append(wsnc.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in self?.setAway(true) })

        observers.append(wsnc.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in self?.setAway(false) })

        observers.append(dnc.addObserver(
            forName: .init("com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] _ in self?.setAway(true) })

        observers.append(dnc.addObserver(
            forName: .init("com.apple.screenIsUnlocked"),
            object: nil, queue: .main) { [weak self] _ in self?.setAway(false) })

        observers.append(dnc.addObserver(
            forName: .init("com.apple.screensaver.didstart"),
            object: nil, queue: .main) { [weak self] _ in self?.setAway(true) })

        observers.append(dnc.addObserver(
            forName: .init("com.apple.screensaver.didstop"),
            object: nil, queue: .main) { [weak self] _ in self?.setAway(false) })
    }

    func stop() {
        let wsnc = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()
        for observer in observers {
            wsnc.removeObserver(observer)
            dnc.removeObserver(observer)
        }
        observers.removeAll()
    }

    func isUserIdle() -> Bool {
        let idleTime = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: CGEventType(rawValue: ~0)!
        )
        guard idleTime >= Self.idleThreshold else { return false }

        if let frontApp = NSWorkspace.shared.frontmostApplication {
            if PowerAssertionChecker.processHasMediaAssertion(pid: frontApp.processIdentifier) {
                return false
            }
        }

        return true
    }

    private func setAway(_ away: Bool) {
        guard isUserAway != away else { return }
        isUserAway = away
        onAwayStateChanged?(away)
    }
}
