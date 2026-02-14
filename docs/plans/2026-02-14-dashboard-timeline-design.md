# Dashboard Timeline Redesign

## Overview

Add a timeline section to the top of the Detail window. The timeline visualizes activity by hour/day with tag colors, provides date navigation, and filters the session table below.

## Timeline Component

### Structure

NSCollectionView with horizontal flow layout. Each cell (`HourCell: NSCollectionViewItem`) contains:

- **`HourBarView: NSView`** — overrides `draw(_:)`, draws colored rectangles bottom-up proportional to tag durations. Unfilled space at top = idle/no activity (transparent).
- **`NSButton`** below the bar — label text depends on mode:
  - Day: "0", "1", ... "23"
  - Week: "Mon", "Tue", ... "Sun"
  - Month: "1", "2", ... "31"
  - On click: filters session table below to that time range. Click again to clear filter.
  - On hover: text becomes bold.

### Color Rules

- Tagged sessions: use `tag.colorLight` / `tag.colorDark` based on `NSApp.effectiveAppearance`
- Untagged active sessions: `NSColor.systemGray`
- Idle/no activity: transparent (unfilled)

### Bar Fill Logic

Bar fills from bottom. Total fill height is proportional to active time in that hour. Within the filled portion, segments are stacked proportionally by tag duration. Example: 40min Work + 20min Personal in 1 hour = bar fills to 100%, bottom 2/3 is Work color, top 1/3 is Personal color.

### Modes

- **Day:** 24 cells (hours 0-23), single row
- **Week:** 7 cells (Mon-Sun), single row, each cell aggregates full day
- **Month:** 28-31 cells (day numbers), single row, each cell aggregates full day

### Dimensions

Total timeline section height = 200pt (navigation bar + bar chart + labels).

## Navigation Header

Row above the timeline collection:

### Left: Date Label

Format depends on mode:
- Day: "Saturday, February 14, 2026"
- Week: "February 10 – 16, 2026"
- Month: "February 2026"

### Center-Right: Navigation Buttons

`< [calendar] >`

- `<` — previous day/week/month (depends on current mode)
- Calendar icon button — opens `NSDatePicker` (calendar style) in a popover
- `>` — next day/week/month

### Calendar Behavior

NSDatePicker returns a specific date. The current segmented control mode determines the range:
- Day mode: shows exactly that day
- Week mode: shows the Mon-Sun week containing that date
- Month mode: shows the entire month of that date

### Far Right: Segmented Control

`NSSegmentedControl` with three segments: "Day", "Week", "Month". Switches the timeline mode, date label format, and collection view data.

## Data Layer

### New DatabaseManager Methods

- `fetchHourlyTagSummaries(for date: Date) -> [Int: [(tagId: Int64?, duration: TimeInterval)]]` — hour (0-23) to tag duration pairs
- `fetchDailyTagSummaries(from: Date, to: Date) -> [Date: [(tagId: Int64?, duration: TimeInterval)]]` — date to tag duration pairs (for Week/Month modes)

Tag resolution uses existing `COALESCE(activity_logs.tag_id, apps.default_tag_id)` logic.

## Interaction: Filtering

When a cell is clicked:
1. The selected hour/day range is stored as a filter
2. The existing session table (below) reloads showing only sessions within that range
3. The selected cell gets visual highlight (e.g. border or brighter background)
4. Clicking the same cell again clears the filter and highlight

## Theme Support

`HourBarView` reads tag colors appropriate for the current appearance. Redraws on `viewDidChangeEffectiveAppearance`.

## Integration

The timeline section is added to the top of `DetailViewController`. The existing Apps/Tags segmented control may be repositioned or removed since the timeline already conveys tag information visually.
