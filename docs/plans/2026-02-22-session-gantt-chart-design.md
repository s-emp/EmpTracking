# Session Gantt Chart Design

## Problem

The detail view shows sessions as a flat list with duration in parentheses (e.g. "09:00 – 09:45 (45мин)"). There is no visual representation of relative session durations — a 20-minute session looks the same as a 1-minute session.

## Solution

Replace the existing timeline section (vertical hour bars) with a Gantt-style chart in Day mode. Each app gets its own horizontal row; sessions appear as colored blocks whose width is proportional to duration.

## Architecture

### Technology

- **Swift Charts** framework (`RectangleMark`) for rendering
- **NSHostingView** to embed SwiftUI chart into the existing AppKit `DetailViewController`

### Data Model

```swift
struct GanttEntry: Identifiable {
    let id = UUID()
    let appName: String      // Y-axis label
    let startTime: Date      // X-axis start
    let endTime: Date        // X-axis end
    let colorIndex: Int      // index into fixed color palette
}
```

### Color Palette

- Fixed palette of ~20 visually pleasant, distinguishable colors
- Color assigned per app via `hash(appName) % palette.count` (stable across sessions)
- Supports light/dark mode
- Not tied to tags

### Data Flow

1. `DetailViewController.loadTableData()` loads `[ActivityLog]` + `[RemoteLog]` (existing)
2. New `updateGanttChart()` method:
   - Filters out `isIdle == true` sessions
   - Resolves app names via existing `appCache`
   - Converts to `[GanttEntry]`
   - Passes to `SessionGanttView`

## UI Component: SessionGanttView

- Uses `Chart` with `RectangleMark(xStart:xEnd:y:)`
- **X-axis:** Time of day. Range = first session start (rounded down to hour) to last session end (rounded up to hour). Hourly tick marks.
- **Y-axis:** App names sorted by total usage time (most active on top). Max 15 apps shown.
- **Block styling:** Rounded corners (3px), colored from palette
- **Height:** Dynamic based on app count (~20px per row, min 120px, max 300px)
- **No interactivity** (view-only, no click/hover actions)

## Integration

### Day Mode

- Hide `timelineCollectionView`
- Show `ganttHostingView` (NSHostingView wrapping SessionGanttView)

### Week/Month Modes

- Hide `ganttHostingView`
- Show `timelineCollectionView` (existing HourBarView/TimelineCell, unchanged)

### Switching

Handled in existing `timelineModeChanged()` — toggle visibility based on mode.

### What Doesn't Change

- Session table below the chart
- Device filter (All / This Mac / Others)
- Date navigation (prev/next/calendar)
- Tag system
- Sync logic

## Files to Create/Modify

- **New:** `SessionGanttView.swift` — SwiftUI view with Swift Charts
- **New:** `GanttColorPalette.swift` — 20-color palette with light/dark support
- **Modify:** `DetailViewController.swift` — add ganttHostingView, toggle visibility, feed data
