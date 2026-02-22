# Session Gantt Chart Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the existing timeline bar section with a Gantt-style chart (in Day mode) where each app gets its own horizontal row and session blocks are proportional to their duration.

**Architecture:** SwiftUI `Chart` with `RectangleMark` embedded via `NSHostingView` into the existing AppKit `DetailViewController`. Data flows from existing `[ActivityLog]`/`[RemoteLog]` arrays through a new `[GanttEntry]` model. A fixed 20-color palette assigns stable colors per app name.

**Tech Stack:** Swift Charts framework, SwiftUI, NSHostingView, AppKit

---

### Task 1: Create GanttColorPalette

**Files:**
- Create: `EmpTracking/Views/GanttColorPalette.swift`

**Step 1: Create the color palette file**

Create `EmpTracking/Views/GanttColorPalette.swift` with this content:

```swift
import SwiftUI

enum GanttColorPalette {
    static let colors: [Color] = [
        Color(red: 0.35, green: 0.56, blue: 0.87),  // Soft blue
        Color(red: 0.27, green: 0.71, blue: 0.56),  // Teal green
        Color(red: 0.90, green: 0.55, blue: 0.34),  // Warm orange
        Color(red: 0.68, green: 0.40, blue: 0.78),  // Soft purple
        Color(red: 0.87, green: 0.43, blue: 0.50),  // Rose
        Color(red: 0.36, green: 0.67, blue: 0.73),  // Cyan
        Color(red: 0.80, green: 0.65, blue: 0.30),  // Goldenrod
        Color(red: 0.55, green: 0.75, blue: 0.40),  // Lime green
        Color(red: 0.78, green: 0.45, blue: 0.65),  // Mauve
        Color(red: 0.45, green: 0.55, blue: 0.70),  // Steel blue
        Color(red: 0.65, green: 0.55, blue: 0.40),  // Tan
        Color(red: 0.50, green: 0.70, blue: 0.60),  // Sage
        Color(red: 0.85, green: 0.50, blue: 0.60),  // Pink
        Color(red: 0.40, green: 0.60, blue: 0.50),  // Forest
        Color(red: 0.75, green: 0.60, blue: 0.50),  // Peach
        Color(red: 0.50, green: 0.50, blue: 0.75),  // Periwinkle
        Color(red: 0.70, green: 0.70, blue: 0.40),  // Olive
        Color(red: 0.60, green: 0.45, blue: 0.55),  // Plum
        Color(red: 0.45, green: 0.65, blue: 0.80),  // Sky blue
        Color(red: 0.75, green: 0.50, blue: 0.35),  // Copper
    ]

    static func color(for appName: String) -> Color {
        let hash = abs(appName.hashValue)
        return colors[hash % colors.count]
    }
}
```

**Step 2: Add to Xcode project**

The file needs to be added to the Xcode project so it compiles. Since the project uses `.xcodeproj`, add the file to the project target.

Run: `open EmpTracking.xcodeproj` (if needed) or use the `PBXProj` script approach. The simplest path: create the file on disk, then reference it from Xcode.

**Step 3: Verify it compiles**

Run: `cd /Users/emp15/Developer/EmpTracking && xcodebuild -scheme EmpTracking -configuration Debug build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add EmpTracking/Views/GanttColorPalette.swift
git commit -m "feat: add 20-color palette for Gantt chart"
```

---

### Task 2: Create GanttEntry model and SessionGanttView

**Files:**
- Create: `EmpTracking/Views/SessionGanttView.swift`

**Step 1: Create SessionGanttView with GanttEntry model**

Create `EmpTracking/Views/SessionGanttView.swift` with this content:

```swift
import SwiftUI
import Charts

struct GanttEntry: Identifiable {
    let id = UUID()
    let appName: String
    let startTime: Date
    let endTime: Date
    let colorIndex: Int
}

struct SessionGanttView: View {
    let entries: [GanttEntry]

    /// Apps sorted by total duration (most active first), max 15.
    private var sortedAppNames: [String] {
        var totals: [String: TimeInterval] = [:]
        for entry in entries {
            totals[entry.appName, default: 0] += entry.endTime.timeIntervalSince(entry.startTime)
        }
        return totals.sorted { $0.value > $1.value }
            .prefix(15)
            .map { $0.key }
    }

    /// X-axis domain: first session start rounded down to hour, last session end rounded up to hour.
    private var timeDomain: ClosedRange<Date> {
        guard let earliest = entries.map(\.startTime).min(),
              let latest = entries.map(\.endTime).max() else {
            let now = Date()
            return now...now.addingTimeInterval(3600)
        }
        let cal = Calendar.current
        let startHour = cal.dateInterval(of: .hour, for: earliest)?.start ?? earliest
        let endComponents = cal.dateComponents([.year, .month, .day, .hour], from: latest)
        var endHour = cal.date(from: endComponents) ?? latest
        if endHour < latest {
            endHour = cal.date(byAdding: .hour, value: 1, to: endHour) ?? latest
        }
        if endHour <= startHour {
            return startHour...startHour.addingTimeInterval(3600)
        }
        return startHour...endHour
    }

    var body: some View {
        let visibleApps = Set(sortedAppNames)
        let visibleEntries = entries.filter { visibleApps.contains($0.appName) }

        Chart(visibleEntries) { entry in
            RectangleMark(
                xStart: .value("Start", entry.startTime),
                xEnd: .value("End", entry.endTime),
                y: .value("App", entry.appName)
            )
            .foregroundStyle(GanttColorPalette.colors[entry.colorIndex % GanttColorPalette.colors.count])
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .chartXScale(domain: timeDomain)
        .chartYScale(domain: sortedAppNames)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 1)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)), centered: false)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel()
            }
        }
    }
}
```

**Step 2: Add to Xcode project and verify build**

Run: `cd /Users/emp15/Developer/EmpTracking && xcodebuild -scheme EmpTracking -configuration Debug build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add EmpTracking/Views/SessionGanttView.swift
git commit -m "feat: add SessionGanttView with Swift Charts Gantt visualization"
```

---

### Task 3: Integrate Gantt chart into DetailViewController

**Files:**
- Modify: `EmpTracking/Views/DetailViewController.swift`

This is the largest task. It has 3 sub-steps.

**Step 1: Add import and ganttHostingView property**

At the top of `DetailViewController.swift`, add `import SwiftUI` after `import Cocoa`.

Add a new property alongside the other UI elements (after line 82, `private var calendarPopover: NSPopover?`):

```swift
private var ganttHostingView: NSView?
private var ganttEntries: [GanttEntry] = []
```

**Step 2: Create and position the ganttHostingView in `loadView()`**

In the `loadView()` method, after the `timelineScrollView` setup (after line 175 `container.addSubview(timelineScrollView)`) add:

```swift
// Gantt chart (SwiftUI via NSHostingView) — shown in Day mode only
let ganttView = SessionGanttView(entries: [])
let hostingView = NSHostingView(rootView: ganttView)
hostingView.translatesAutoresizingMaskIntoConstraints = false
hostingView.isHidden = true  // hidden initially, shown when Day mode + data loaded
container.addSubview(hostingView)
ganttHostingView = hostingView
```

Then in the `NSLayoutConstraint.activate` block, add constraints for `hostingView` that match the `timelineScrollView` position exactly:

```swift
hostingView.topAnchor.constraint(equalTo: timelineBackgroundView.topAnchor, constant: 4),
hostingView.leadingAnchor.constraint(equalTo: timelineBackgroundView.leadingAnchor, constant: 4),
hostingView.trailingAnchor.constraint(equalTo: timelineBackgroundView.trailingAnchor, constant: -4),
hostingView.heightAnchor.constraint(equalToConstant: timelineHeight),
```

**Step 3: Add updateGanttChart() method and wire up visibility toggling**

Add a new method after `loadTimelineData()`:

```swift
private func updateGanttChart() {
    guard timelineMode == .day else {
        ganttHostingView?.isHidden = true
        timelineScrollView.isHidden = false
        return
    }

    // Build GanttEntry array from current loaded data
    var entries: [GanttEntry] = []

    // Local logs
    for log in logs where !log.isIdle {
        let appInfo = appCache[log.appId]
        let appName = appInfo?.appName ?? "Unknown"
        let colorIndex = abs(appName.hashValue) % GanttColorPalette.colors.count
        entries.append(GanttEntry(
            appName: appName,
            startTime: log.startTime,
            endTime: log.endTime,
            colorIndex: colorIndex
        ))
    }

    // Remote logs
    for log in remoteLogs where !log.isIdle {
        let colorIndex = abs(log.appName.hashValue) % GanttColorPalette.colors.count
        entries.append(GanttEntry(
            appName: log.appName,
            startTime: log.startTime,
            endTime: log.endTime,
            colorIndex: colorIndex
        ))
    }

    ganttEntries = entries

    // Update the SwiftUI view
    if let hostingView = ganttHostingView as? NSHostingView<SessionGanttView> {
        hostingView.rootView = SessionGanttView(entries: entries)
    }

    // Toggle visibility
    ganttHostingView?.isHidden = false
    timelineScrollView.isHidden = true
}
```

**Step 4: Call updateGanttChart() from reload()**

Modify the `reload()` method (line 346-351) to call `updateGanttChart()` after loading data. The updated method:

```swift
func reload() {
    updateDateLabel()
    loadTimelineData()
    timelineCollectionView.reloadData()
    reloadTable()
    updateGanttChart()
}
```

**Step 5: Update timelineModeChanged to toggle visibility**

The existing `timelineModeChanged(_:)` already calls `reload()` which will now call `updateGanttChart()`, so visibility toggling is handled automatically. No extra change needed here.

**Step 6: Also update the appearance observer to refresh Gantt**

In `viewDidAppear()`, update the appearance observation block (line 660-663) to also refresh the gantt chart:

```swift
appearanceObservation = view.observe(\.effectiveAppearance) { [weak self] _, _ in
    self?.timelineCollectionView.reloadData()
    self?.updateTimelineBackgroundColor()
    self?.updateGanttChart()
}
```

**Step 7: Build and verify**

Run: `cd /Users/emp15/Developer/EmpTracking && xcodebuild -scheme EmpTracking -configuration Debug build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 8: Commit**

```bash
git add EmpTracking/Views/DetailViewController.swift
git commit -m "feat: integrate Gantt chart into DetailViewController for Day mode"
```

---

### Task 4: Manual testing and visual polish

**Step 1: Build and run the app**

Run: `cd /Users/emp15/Developer/EmpTracking && xcodebuild -scheme EmpTracking -configuration Debug build 2>&1 | tail -5`

Launch the app and open the Detail window. Verify:
- In **Day mode**: the old vertical hour bars are replaced by a Gantt chart with horizontal bars per app
- In **Week mode**: the old vertical bars still appear
- In **Month mode**: the old vertical bars still appear
- Switching between modes toggles correctly
- Apps have distinct colors from the palette
- Session blocks are proportionally sized (long sessions = wide blocks, short = narrow)
- Dark mode / Light mode both look correct

**Step 2: Fix any visual issues**

Potential adjustments:
- If chart height feels wrong, adjust the `timelineHeight` constant or make it dynamic based on app count
- If Y-axis labels are too long/truncated, consider truncating app names
- If colors don't look good in dark mode, adjust the palette

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: session Gantt chart - visual polish"
```

---

### Task 5: Device filter integration

**Step 1: Verify device filter affects Gantt chart**

The `updateGanttChart()` method reads from `logs` and `remoteLogs` which are already filtered by `loadTableData()` based on `deviceFilter`. However, `updateGanttChart()` is called from `reload()`, which calls `reloadTable()` → `loadTableData()` first.

Check: when switching device filter (All / This Mac / Others), the gantt chart should also update. Currently `deviceFilterChanged` calls `reloadTable()` but NOT `reload()`. We need `updateGanttChart()` to also be called.

**Step 2: Update deviceFilterChanged**

Modify `deviceFilterChanged(_:)` (line 339-342):

```swift
@objc private func deviceFilterChanged(_ sender: NSSegmentedControl) {
    deviceFilter = DeviceFilter(rawValue: sender.selectedSegment) ?? .thisMac
    reloadTable()
    updateGanttChart()
}
```

**Step 3: Build, verify, commit**

Run: `cd /Users/emp15/Developer/EmpTracking && xcodebuild -scheme EmpTracking -configuration Debug build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

```bash
git add EmpTracking/Views/DetailViewController.swift
git commit -m "fix: update Gantt chart when device filter changes"
```
