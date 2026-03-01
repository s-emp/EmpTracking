# Gantt Chart Tag Selection Design

**Date:** 2026-02-25
**Status:** Approved

## Summary

Add interactive selection and tag assignment to `SessionGanttView` in the Stats window. Users can click individual blocks or drag to select time ranges, with Shift for multi-selection. Right-click shows a popover to assign tags.

## Approach

**Approach 2: Full custom gestures via `chartOverlay` + `ChartProxy`** — manual coordinate conversion, full control over selection behavior.

## Data Model

### GanttEntry (modified)

```swift
struct GanttEntry: Identifiable {
    let id = UUID()
    let appName: String
    let startTime: Date
    let endTime: Date
    let colorIndex: Int
    let logIds: [Int64]    // ActivityLog IDs behind this block
    let tagId: Int64?      // current tag (if assigned)
}
```

### GanttSelectionState (new)

```swift
@Observable
class GanttSelectionState {
    var selectedEntryIds: Set<UUID> = []   // selected blocks
    var dragRange: ClosedRange<Date>?      // time range during drag
}
```

## Interaction Model

### Click (TapGesture)
1. Convert click coordinates via `proxy.value(atX:)` and `proxy.value(atY:)` → get `Date` and `appName`
2. Find `GanttEntry` containing that point (startTime...endTime + appName match)
3. Without Shift → `selectedEntryIds = [entry.id]`
4. With Shift (`NSEvent.modifierFlags.contains(.shift)`) → toggle entry in set
5. Click on empty area (no entry hit) → clear selection

### Drag (DragGesture)
1. On `.onChanged` — convert start/current positions to `Date` via `proxy.value(atX:)`
2. Update `dragRange` — show translucent overlay
3. On `.onEnded` — find all entries overlapping with range
4. Without Shift → `selectedEntryIds = overlapping`
5. With Shift → `selectedEntryIds.formUnion(overlapping)`

### Right-click
- `NSClickGestureRecognizer(buttonMask: 0x2)` via NSViewRepresentable wrapper or `.contextMenu`
- If right-clicked on a block not in selection → select it first, then show popover
- If there's an existing selection → show popover for all selected
- Empty area right-click → no action

### Deselection
- Click on empty area (no Shift) → clear `selectedEntryIds`
- Escape key → clear selection

## Visual Design

### Selected blocks
- Bright border (2pt, `NSColor.Semantic.actionPrimary`)
- Light highlight overlay

### Drag selection (while dragging)
- Translucent rectangle (`RectangleMark`) across full chart height for selected time range
- Color: `actionPrimary.opacity(0.15)`

### Tagged blocks
- Blocks with assigned tag get colored stroke (2pt, tag color from `tag.colorLight/colorDark` respecting appearance)
- Blocks without tag — no stroke (current behavior)

### Tag Popover
- Compact list of tags (colored circle + name)
- "Remove tag" button if selected blocks already have a tag
- Appears near right-click location
- Selecting tag → assign to all selected → close popover → clear selection

## Database Changes

### New method: `setTagForLogs`
```swift
func setTagForLogs(logIds: [Int64], tagId: Int64?) throws
```
Single SQL UPDATE for batch tag assignment. Replaces multiple `setSessionTag()` calls.

## Data Flow

1. `StatsViewController` loads logs → builds `GanttEntry` with `logIds` and `tagId` from `ActivityLog`
2. `SessionGanttView` receives entries + `GanttSelectionState` + `[Tag]` list
3. User selects → right-click → picks tag
4. Callback `onTagAssigned(logIds: [Int64], tagId: Int64?)` → StatsViewController calls `db.setTagForLogs()` → reloads data
5. Gantt redraws with updated tag borders

## Files to Modify

| File | Changes |
|------|---------|
| `Sources/Views/SessionGanttView.swift` | Add selection state, chartOverlay gestures, visual selection/tag rendering |
| `Sources/Models/GanttEntry.swift` (extract) | Add `logIds`, `tagId` fields |
| `Sources/Views/Stats/TagPopoverView.swift` (new) | Tag selection popover |
| `Sources/Views/Stats/GanttSelectionState.swift` (new) | Observable selection state |
| `Sources/Services/DatabaseManager.swift` | Add `setTagForLogs()` batch method |
| `Sources/Views/Stats/StatsViewController.swift` | Pass `logIds`/`tagId` when building GanttEntry, handle tag assignment callback |
