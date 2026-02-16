import XCTest
import SnapshotTesting
@testable import EmpTracking

final class TimelineSnapshotTests: XCTestCase {
    func testTimelineCellAppearance() {
        let cell = TimelineCell()
        cell.loadView()
        cell.view.frame = NSRect(x: 0, y: 0, width: 40, height: 160)
        cell.configure(
            label: "10",
            segments: [
                (color: .systemBlue, fraction: 0.4),
                (color: .systemGreen, fraction: 0.3),
                (color: .systemOrange, fraction: 0.15),
            ]
        )
        cell.showSeparator = true
        cell.view.layoutSubtreeIfNeeded()

        assertSnapshot(of: cell.view, as: .image(precision: 0.95))
    }

    func testTimelineCellEmpty() {
        let cell = TimelineCell()
        cell.loadView()
        cell.view.frame = NSRect(x: 0, y: 0, width: 40, height: 160)
        cell.configure(label: "0", segments: [])
        cell.showSeparator = true
        cell.view.layoutSubtreeIfNeeded()

        assertSnapshot(of: cell.view, as: .image(precision: 0.95))
    }

    func testTimelineCellHighlighted() {
        let cell = TimelineCell()
        cell.loadView()
        cell.view.frame = NSRect(x: 0, y: 0, width: 40, height: 160)
        cell.configure(
            label: "14",
            segments: [
                (color: .systemPurple, fraction: 0.6),
                (color: .systemTeal, fraction: 0.2),
            ]
        )
        cell.isHighlighted = true
        cell.showSeparator = false
        cell.view.layoutSubtreeIfNeeded()

        assertSnapshot(of: cell.view, as: .image(precision: 0.95))
    }
}
