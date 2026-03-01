# Stats Window Redesign Design

## Overview

Full redesign of the DetailViewController (statistics window) with a new layout inspired by the HTML mockup at `~/Downloads/time-tracker-stats.html`. Uses EmpDesignSystem v0.2.0 components, colors, and gradients. Charts via SwiftUI Charts. Tags functionality removed from UI (backend unchanged).

## Requirements

- Replace DetailViewController with new StatsViewController
- Window size: 1280x820, resizable (min 900x600)
- Framework: AppKit + SwiftUI Charts (NSHostingView)
- Design System: EmpUI_macOS v0.2.0
- Sections: Toolbar, Timeline (Gantt), Applications (Donut + list), Summary (4 gradient metric cards)
- No tags in UI
- Device filter preserved (All / This Mac / others)
- Day/Week navigation with calendar picker

## Architecture

Single `StatsViewController` (NSViewController) with child views for each section:

```
StatsViewController
├── StatsToolbarView (NSView)
│   ├── EmpText (date label)
│   ├── EmpSegmentControl (Day/Week)
│   ├── EmpButton (‹ prev)
│   ├── EmpButton (calendar)
│   ├── EmpButton (next ›)
│   └── NSPopUpButton (device filter)
├── NSScrollView
│   ├── TimelineSectionView (NSView)
│   │   ├── EmpText (section label "TIMELINE")
│   │   └── NSHostingView<GanttChartView> (SwiftUI Charts)
│   └── TwoColumnView (NSView)
│       ├── ApplicationsSectionView (55%)
│       │   ├── EmpText (section label "APPLICATIONS")
│       │   └── ApplicationsCardView (NSView, rounded, backgroundSecondary)
│       │       ├── NSHostingView<DonutChartView> (left side, SwiftUI Charts)
│       │       └── AppsListView (right side, NSStackView)
│       │           └── AppRowView[] (EmpImage + EmpText + EmpText + EmpProgressBar)
│       └── SummarySectionView (45%)
│           ├── EmpText (section label "SUMMARY")
│           └── MetricsGridView (2x2 grid)
│               └── EmpInfoCard[4] (Preset.gradient)
```

## Sections Detail

### Toolbar (52px height)

- **Date label**: Left-aligned, `EmpText` with 14pt semibold, `textPrimary`
- **Segment control**: `EmpSegmentControl` with segments `["Day", "Week"]`
- **Navigation**: `EmpButton.Preset.ghost(.primary)` for ‹ and › buttons, calendar button
- **Calendar**: `NSDatePicker` in popover on calendar button click
- **Device filter**: `NSPopUpButton` right-aligned, items from `SyncManager.knownDevices`
- **Background**: `backgroundPrimary`, bottom border `borderSubtle`

### Timeline (Gantt)

- Section label: `EmpText` "TIMELINE", 11pt semibold, `textTertiary`, uppercase
- Card: `backgroundSecondary`, rounded corners 12px
- Chart: SwiftUI `Chart` with `BarMark` for each app session
  - X axis: hours of day (6:00-22:00)
  - Y axis: app names
  - Colors: from `GanttColorPalette`
  - Tooltip on hover showing app name and time range
- Data: `DatabaseManager.fetchActivityLogs()` for selected date, grouped by app
- Week mode: stacked bar chart by day instead of Gantt

### Applications

- Section label: `EmpText` "APPLICATIONS"
- Card container: `backgroundSecondary`, rounded corners 12px
- Left side (180px): Donut chart (SwiftUI `SectorMark`) + legend below
  - Center label: total time
  - Colors: `GanttColorPalette`
- Right side: scrollable list of apps
  - Each row: `EmpImage` (app icon) + `EmpText` (name) + `EmpText` (time) + `EmpText` (percentage) + `EmpProgressBar`
  - Sorted by duration descending
- Data: `DatabaseManager.fetchAppSummaries()` for selected date/range

### Summary (2x2 Grid)

All cards use `EmpInfoCard.Preset.gradient()`:

| Card | Subtitle | Data | Gradient |
|------|----------|------|----------|
| Total Time | "TOTAL TIME" | Sum of all activity | `lavenderToSky` |
| Active Time | "ACTIVE TIME" | Total minus idle | `skyToMint` |
| Longest Session | "LONGEST SESSION" | Max single session duration | `peachToRose` |
| Apps Used | "APPS USED" | Count of distinct apps | `lavenderToLilac` |

## Colors & Styling

- Window background: `NSColor.Semantic.backgroundPrimary`
- Card backgrounds: `NSColor.Semantic.backgroundSecondary`
- Dividers: `NSColor.Semantic.borderSubtle`
- Text hierarchy: `textPrimary` > `textSecondary` > `textTertiary`
- App colors: `GanttColorPalette` (existing 20 colors)
- Gradient cards: `EmpGradient.Preset.*`
- Spacing: `EmpSpacing` tokens throughout
- Corner radius: 12px for cards (via `CommonViewModel.Corners`)

## Components from EmpDesignSystem

| Component | Usage |
|-----------|-------|
| `EmpSegmentControl` | Day/Week switcher |
| `EmpInfoCard` | 4 gradient summary cards |
| `EmpText` | All labels and text |
| `EmpImage` | App icons |
| `EmpProgressBar` | App usage bars in list |
| `EmpButton` | Navigation ‹ ›, calendar |
| `NSColor.Semantic.*` | All colors |
| `NSColor.Base.*` | Chart colors where needed |
| `EmpGradient.Preset.*` | Card gradients |
| `EmpSpacing` | All spacing |
| `CommonViewModel` | Corners, borders, shadows |

## Custom (not from DS)

| Element | Implementation | Reason |
|---------|---------------|--------|
| Gantt chart | SwiftUI Charts `BarMark` in `NSHostingView` | No chart components in DS |
| Donut chart | SwiftUI Charts `SectorMark` in `NSHostingView` | No chart components in DS |
| Calendar picker | `NSDatePicker` in popover | Standard macOS control |
| Device filter | `NSPopUpButton` | Standard macOS control |
| Layout containers | `NSView` + Auto Layout | Structural, not DS components |
| Scroll view | `NSScrollView` | Standard macOS control |

## Data Flow

```
StatsViewController
    │
    ├── dateRange (computed from selectedDate + mode Day/Week)
    ├── deviceFilter (All / specific device)
    │
    ├──► DatabaseManager.fetchAppSummaries(since:until:deviceId:)
    │        → AppSummary[] → Donut chart, Apps list, Summary cards
    │
    ├──► DatabaseManager.fetchActivityLogs(since:until:deviceId:)
    │        → ActivityLog[] → Gantt chart
    │
    └──► SyncManager.knownDevices → Device filter popup
```

## Files to Create/Modify

### New files:
- `Sources/Views/Stats/StatsViewController.swift` — main controller
- `Sources/Views/Stats/StatsToolbarView.swift` — toolbar
- `Sources/Views/Stats/GanttChartView.swift` — SwiftUI Gantt chart
- `Sources/Views/Stats/DonutChartView.swift` — SwiftUI Donut chart
- `Sources/Views/Stats/ApplicationsCardView.swift` — apps card with donut + list
- `Sources/Views/Stats/AppRowView.swift` — single app row
- `Sources/Views/Stats/MetricsGridView.swift` — 2x2 grid of EmpInfoCard

### Modified files:
- `Sources/AppDelegate.swift` — wire new StatsViewController instead of DetailViewController
- `Sources/Services/DatabaseManager.swift` — add query methods if needed for new data (longest session, device filtering)

### Removed from UI (files kept):
- `Sources/Views/DetailViewController.swift` — no longer used as main stats view
- `Sources/Views/DetailCellView.swift` — tag-related cell
- `Sources/Views/TagCellView.swift` — tag-related cell
- `Sources/Views/HourBarView.swift` — replaced by SwiftUI charts
- `Sources/Views/TimelineCell.swift` — replaced by SwiftUI charts
