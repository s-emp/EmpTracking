# Gantt Tag Selection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add interactive selection and tag assignment to SessionGanttView — click blocks, drag ranges, Shift for multi-select, right-click popover to assign tags.

**Architecture:** Custom gesture handling via `chartOverlay` + `ChartProxy` on the existing SwiftUI Chart. New `GanttSelectionState` observable drives selection UI. Tag popover via `NSPopover`. Tag borders via `RectangleMark` stroke overlay.

**Tech Stack:** SwiftUI Charts, AppKit (NSPopover, NSEvent), Observation framework

---

### Task 1: Extend GanttEntry with logIds and tagId

**Files:**
- Modify: `Sources/Views/SessionGanttView.swift:4-10`

**Step 1: Add fields to GanttEntry**

Replace the current `GanttEntry` struct:

```swift
struct GanttEntry: Identifiable {
    let id = UUID()
    let appName: String
    let startTime: Date
    let endTime: Date
    let colorIndex: Int
    let logIds: [Int64]
    let tagId: Int64?
}
```

**Step 2: Fix all GanttEntry init call sites**

In `Sources/Views/Stats/StatsViewController.swift:572-577`, update local log entries:

```swift
entries.append(GanttEntry(
    appName: appName,
    startTime: log.startTime,
    endTime: log.endTime,
    colorIndex: GanttColorPalette.colorIndex(for: appName),
    logIds: [log.id],
    tagId: log.tagId
))
```

In `Sources/Views/Stats/StatsViewController.swift:583-588`, update remote log entries:

```swift
entries.append(GanttEntry(
    appName: log.appName,
    startTime: log.startTime,
    endTime: log.endTime,
    colorIndex: GanttColorPalette.colorIndex(for: log.appName),
    logIds: [],
    tagId: nil
))
```

**Step 3: Update mergeEntries to accumulate logIds**

In `Sources/Views/Stats/StatsViewController.swift:596-623`, update the merge logic:

```swift
private func mergeEntries(_ entries: [GanttEntry], threshold: TimeInterval) -> [GanttEntry] {
    let grouped = Dictionary(grouping: entries) { $0.appName }
    var result: [GanttEntry] = []

    for (_, appEntries) in grouped {
        let sorted = appEntries.sorted { $0.startTime < $1.startTime }
        var merged = [GanttEntry]()

        for entry in sorted {
            if let last = merged.last,
               entry.startTime.timeIntervalSince(last.endTime) < threshold {
                let combined = GanttEntry(
                    appName: last.appName,
                    startTime: last.startTime,
                    endTime: max(last.endTime, entry.endTime),
                    colorIndex: last.colorIndex,
                    logIds: last.logIds + entry.logIds,
                    tagId: last.tagId ?? entry.tagId
                )
                merged[merged.count - 1] = combined
            } else {
                merged.append(entry)
            }
        }

        result.append(contentsOf: merged)
    }

    return result
}
```

**Step 4: Build and verify no compilation errors**

Run: `tuist generate && xcodebuild -scheme EmpTracking -configuration Debug build`
Expected: BUILD SUCCEEDED

---

### Task 2: Create GanttSelectionState

**Files:**
- Create: `Sources/Views/Stats/GanttSelectionState.swift`

**Step 1: Create the observable selection state**

```swift
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
```

**Step 2: Build and verify**

Run: `tuist generate && xcodebuild -scheme EmpTracking -configuration Debug build`
Expected: BUILD SUCCEEDED

---

### Task 3: Add batch tag assignment to DatabaseManager

**Files:**
- Modify: `Sources/Services/DatabaseManager.swift` (after `setSessionTag` at line ~503)

**Step 1: Add setTagForLogs method**

Add after the existing `setSessionTag` method (line 503):

```swift
func setTagForLogs(logIds: [Int64], tagId: Int64?) throws {
    guard !logIds.isEmpty else { return }
    let placeholders = logIds.map { _ in "?" }.joined(separator: ",")
    let sql = "UPDATE activity_logs SET tag_id = \(tagId == nil ? "NULL" : "?") WHERE id IN (\(placeholders))"
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }

    var bindIndex: Int32 = 1
    if let tagId = tagId {
        sqlite3_bind_int64(stmt, bindIndex, tagId)
        bindIndex += 1
    }
    for id in logIds {
        sqlite3_bind_int64(stmt, bindIndex, id)
        bindIndex += 1
    }

    if sqlite3_step(stmt) != SQLITE_DONE {
        throw DBError.updateFailed(String(cString: sqlite3_errmsg(db)))
    }
}
```

**Step 2: Build and verify**

Run: `tuist generate && xcodebuild -scheme EmpTracking -configuration Debug build`
Expected: BUILD SUCCEEDED

---

### Task 4: Create TagPopoverView

**Files:**
- Create: `Sources/Views/Stats/TagPopoverView.swift`

**Step 1: Create the tag picker SwiftUI view**

```swift
import SwiftUI

struct TagPopoverView: View {
    let tags: [Tag]
    let onSelect: (Int64?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(tags, id: \.id) { tag in
                Button {
                    onSelect(tag.id)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(tagColor(tag))
                            .frame(width: 10, height: 10)
                        Text(tag.name)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .cornerRadius(4)
            }

            Divider()

            Button {
                onSelect(nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("Remove tag")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(width: 180)
    }

    private func tagColor(_ tag: Tag) -> Color {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let hex = isDark ? tag.colorDark : tag.colorLight
        return Color(nsColor: NSColor(hex: hex))
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
```

**Step 2: Build and verify**

Run: `tuist generate && xcodebuild -scheme EmpTracking -configuration Debug build`
Expected: BUILD SUCCEEDED

---

### Task 5: Add selection gestures and visual overlays to SessionGanttView

**Files:**
- Modify: `Sources/Views/SessionGanttView.swift`

This is the core task. Replace the entire `SessionGanttView` body with gesture handling, selection highlights, and tag borders.

**Step 1: Update SessionGanttView signature to accept selection state and tags**

```swift
struct SessionGanttView: View {
    let entries: [GanttEntry]
    var selectionState: GanttSelectionState? = nil
    var tags: [Tag] = []
    var onTagAssigned: (([Int64], Int64?) -> Void)? = nil
```

**Step 2: Add helper to find entry at point**

```swift
private func entryAt(date: Date, appName: String?) -> GanttEntry? {
    entries.first { entry in
        entry.startTime <= date && date <= entry.endTime
            && (appName == nil || entry.appName == appName)
    }
}
```

**Step 3: Add tag color lookup helper**

```swift
private func tagBorderColor(for tagId: Int64) -> Color? {
    guard let tag = tags.first(where: { $0.id == tagId }) else { return nil }
    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let hex = isDark ? tag.colorDark : tag.colorLight
    return Color(nsColor: NSColor(hex: hex))
}
```

Note: reuse the `NSColor(hex:)` extension from TagPopoverView — extract it to a shared file or duplicate in the same module scope (since both are internal).

**Step 4: Replace the body with gesture overlay**

```swift
var body: some View {
    let names = sortedAppNames
    let visibleApps = Set(names)
    let visibleEntries = entries.filter { visibleApps.contains($0.appName) }
    let chartHeight = CGFloat(names.count) * Self.rowHeight

    ScrollView(.vertical) {
        Chart {
            ForEach(visibleEntries) { entry in
                RectangleMark(
                    xStart: .value("Start", entry.startTime),
                    xEnd: .value("End", entry.endTime),
                    y: .value("App", entry.appName)
                )
                .foregroundStyle(GanttColorPalette.colors[entry.colorIndex % GanttColorPalette.colors.count])
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .opacity(entryOpacity(entry))
            }

            // Tag borders as separate overlay marks
            ForEach(visibleEntries.filter { $0.tagId != nil }) { entry in
                if let borderColor = tagBorderColor(for: entry.tagId!) {
                    RectangleMark(
                        xStart: .value("Start", entry.startTime),
                        xEnd: .value("End", entry.endTime),
                        y: .value("App", entry.appName)
                    )
                    .foregroundStyle(.clear)
                    .border(borderColor, width: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }

            // Selection highlight borders
            if let state = selectionState {
                ForEach(visibleEntries.filter { state.selectedEntryIds.contains($0.id) }) { entry in
                    RectangleMark(
                        xStart: .value("Start", entry.startTime),
                        xEnd: .value("End", entry.endTime),
                        y: .value("App", entry.appName)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }

            // Drag range overlay
            if let range = selectionState?.dragRange {
                RectangleMark(
                    xStart: .value("Start", range.lowerBound),
                    xEnd: .value("End", range.upperBound)
                )
                .foregroundStyle(Color.accentColor.opacity(0.1))
            }
        }
        .chartXScale(domain: timeDomain)
        .chartYScale(domain: names)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 1)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)), centered: false)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
            }
        }
        .chartPlotStyle { plotArea in
            plotArea.frame(height: max(chartHeight, 100))
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                guard let state = selectionState else { return }
                                let origin = geometry[proxy.plotAreaFrame].origin
                                let startX = value.startLocation.x - origin.x
                                let currentX = value.location.x - origin.x
                                if let startDate = proxy.value(atX: startX) as Date?,
                                   let currentDate = proxy.value(atX: currentX) as Date? {
                                    state.dragStart = startDate
                                    state.dragEnd = currentDate
                                }
                            }
                            .onEnded { _ in
                                guard let state = selectionState,
                                      let range = state.dragRange else { return }
                                let additive = NSEvent.modifierFlags.contains(.shift)
                                state.selectOverlapping(entries: entries, range: range, additive: additive)
                                state.dragStart = nil
                                state.dragEnd = nil
                            }
                    )
                    .onTapGesture { location in
                        guard let state = selectionState else { return }
                        let origin = geometry[proxy.plotAreaFrame].origin
                        let x = location.x - origin.x
                        guard let date = proxy.value(atX: x) as Date? else { return }

                        // Try to find which app row was clicked
                        let y = location.y - origin.y
                        let appName = proxy.value(atY: y) as String?

                        let additive = NSEvent.modifierFlags.contains(.shift)

                        if let entry = entryAt(date: date, appName: appName) {
                            if additive {
                                state.toggle(entry.id)
                            } else {
                                state.selectedEntryIds = [entry.id]
                            }
                        } else if !additive {
                            state.clear()
                        }
                    }
            }
        }
    }
}

private func entryOpacity(_ entry: GanttEntry) -> Double {
    guard let state = selectionState, state.hasSelection else { return 1.0 }
    return state.selectedEntryIds.contains(entry.id) ? 1.0 : 0.5
}
```

**Step 5: Build and verify**

Run: `tuist generate && xcodebuild -scheme EmpTracking -configuration Debug build`
Expected: BUILD SUCCEEDED

---

### Task 6: Wire up selection state and tag popover in StatsViewController

**Files:**
- Modify: `Sources/Views/Stats/StatsViewController.swift`

**Step 1: Add selection state and tags properties**

Add to the `// MARK: - State` section (after line 19):

```swift
private let ganttSelection = GanttSelectionState()
private var allTags: [Tag] = []
private var tagPopover: NSPopover?
```

**Step 2: Load tags in loadData**

Add to `loadData(from:to:)` (after line 557, before the catch):

```swift
allTags = try db.fetchAllTags()
```

**Step 3: Update updateGantt to pass selection state, tags, and callback**

Replace line 593 (`ganttHostingView.rootView = SessionGanttView(entries: merged)`):

```swift
ganttHostingView.rootView = SessionGanttView(
    entries: merged,
    selectionState: ganttSelection,
    tags: allTags,
    onTagAssigned: { [weak self] logIds, tagId in
        self?.handleTagAssignment(logIds: logIds, tagId: tagId)
    }
)
```

**Step 4: Add right-click gesture recognizer for tag popover**

Add to `setupContent(in:)`, after adding `ganttHostingView` to `timelineCard` (after line 250):

```swift
let rightClick = NSClickGestureRecognizer(target: self, action: #selector(ganttRightClicked(_:)))
rightClick.buttonMask = 0x2
ganttHostingView.addGestureRecognizer(rightClick)
```

**Step 5: Add right-click handler and tag assignment method**

Add new methods to StatsViewController:

```swift
@objc private func ganttRightClicked(_ gesture: NSClickGestureRecognizer) {
    guard ganttSelection.hasSelection else { return }
    let location = gesture.location(in: ganttHostingView)

    let selectedLogIds = ganttSelection.selectedEntryIds.compactMap { selectedId in
        // find the entry matching this id from the current gantt rootView
        // We need to store merged entries as a property
    }

    showTagPopover(relativeTo: location)
}

private func showTagPopover(relativeTo point: NSPoint) {
    tagPopover?.close()

    let selectedEntries = currentGanttEntries.filter { ganttSelection.selectedEntryIds.contains($0.id) }
    let logIds = selectedEntries.flatMap(\.logIds)
    guard !logIds.isEmpty else { return }

    let popoverView = TagPopoverView(tags: allTags) { [weak self] tagId in
        self?.tagPopover?.close()
        self?.tagPopover = nil
        self?.handleTagAssignment(logIds: logIds, tagId: tagId)
    }

    let hostingVC = NSHostingController(rootView: popoverView)
    let popover = NSPopover()
    popover.contentViewController = hostingVC
    popover.behavior = .transient

    let rect = NSRect(x: point.x, y: point.y, width: 1, height: 1)
    popover.show(relativeTo: rect, of: ganttHostingView, preferredEdge: .minY)
    tagPopover = popover
}

private func handleTagAssignment(logIds: [Int64], tagId: Int64?) {
    do {
        try db.setTagForLogs(logIds: logIds, tagId: tagId)
        ganttSelection.clear()
        reload()
    } catch {
        print("Error assigning tag: \(error)")
    }
}
```

**Step 6: Store current merged entries as property for right-click lookups**

Add property to StatsViewController (in `// MARK: - Data` section):

```swift
private var currentGanttEntries: [GanttEntry] = []
```

Update `updateGantt` — before the `ganttHostingView.rootView = ...` line, add:

```swift
currentGanttEntries = merged
```

**Step 7: Add Escape key handler to clear selection**

```swift
override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { // Escape
        ganttSelection.clear()
    } else {
        super.keyDown(with: event)
    }
}
```

**Step 8: Build, run, and manually verify**

Run: `tuist generate && xcodebuild -scheme EmpTracking -configuration Debug build`
Expected: BUILD SUCCEEDED

Manual verification:
1. Open Stats window
2. Click on a Gantt block → it highlights (others dim to 50% opacity)
3. Shift+click another block → both highlighted
4. Drag across time range → all overlapping blocks selected
5. Right-click on selection → popover with tag list appears
6. Select a tag → blocks get colored border, selection clears
7. Click empty area → selection clears
8. Press Escape → selection clears

---

### Task 7: Extract shared NSColor hex extension

**Files:**
- Create: `Sources/Extensions/NSColor+Hex.swift`

**Step 1: Create shared extension**

```swift
import Cocoa

extension NSColor {
    convenience init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
```

**Step 2: Remove the private extension from TagPopoverView.swift**

Remove the `private extension NSColor` block at the bottom of `Sources/Views/Stats/TagPopoverView.swift`.

**Step 3: Build and verify**

Run: `tuist generate && xcodebuild -scheme EmpTracking -configuration Debug build`
Expected: BUILD SUCCEEDED
