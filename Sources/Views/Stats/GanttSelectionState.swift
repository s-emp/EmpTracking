import SwiftUI

@Observable
final class GanttSelectionState {
    var selectedEntryIds: Set<UUID> = []
    var dragStart: Date?
    var dragEnd: Date?

    var dragRange: ClosedRange<Date>? {
        guard let s = dragStart, let e = dragEnd else { return nil }
        let lo = min(s, e)
        let hi = max(s, e)
        guard lo < hi else { return nil }
        return lo...hi
    }

    var hasSelection: Bool {
        !selectedEntryIds.isEmpty
    }

    func clear() {
        selectedEntryIds.removeAll()
        dragStart = nil
        dragEnd = nil
    }

    func toggle(_ id: UUID) {
        if selectedEntryIds.contains(id) {
            selectedEntryIds.remove(id)
        } else {
            selectedEntryIds.insert(id)
        }
    }

    func selectOverlapping(entries: [GanttEntry], range: ClosedRange<Date>, additive: Bool) {
        let overlapping = entries.filter { entry in
            entry.startTime < range.upperBound && entry.endTime > range.lowerBound
        }
        let ids = Set(overlapping.map(\.id))
        if additive {
            selectedEntryIds.formUnion(ids)
        } else {
            selectedEntryIds = ids
        }
    }
}
