# Status Bar Popover Refactor Design

**Date:** 2026-02-23
**Reference:** ~/Pictures/CleanShot/Figma_001584@2x.png

## Goal

Refactor the status bar popover window to match Figma design, using EmpDesignSystem components. Add right-click context menu on the status bar icon.

## Rules

1. Use only EmpDesignSystem components (EmpText, EmpImage, EmpProgressBar, EmpButton)
2. If a component is missing — stop and report what's needed
3. Assemble cells from existing DS components inside EmpTracking (no new DS components)

## Design Decisions

| Decision | Choice |
|----------|--------|
| Cell component | Assemble from DS components in EmpTracking (no EmpCell in DS) |
| Right-click menu | Standard NSMenu |
| Bottom buttons | Remove from popover → move to right-click menu |
| Segmented control | Remove (apps-only mode in popover, tags available in Detail window) |
| "Show more..." | Opens Detail window (same as current "Подробнее") |
| Sync menu item | Shows last sync time: "Синхронизация — HH:mm" |

## Popover Layout

```
┌──────────────────────────────────────┐
│  February 22              13h 45min  │  Header
│──────────────────────────────────────│  Separator
│                                      │
│  [icon] Safari              5h 22min │  Cell row
│  ████████████░░░░░░░░░░░░░░░░░░░░░░ │  Progress bar
│──────────────────────────────────────│  Separator
│  [icon] Figma               3h 15min │
│  █████████░░░░░░░░░░░░░░░░░░░░░░░░░ │
│──────────────────────────────────────│
│  ... more rows ...                   │
│──────────────────────────────────────│
│            Show more...              │  Footer button
└──────────────────────────────────────┘
```

### Header
- Left: date text — `EmpText`, secondary color, 14pt
- Right: total time — `EmpText`, primary color, bold, 16pt+
- Spacing: `EmpSpacing.m` (16pt) padding

### Cell Row
- App icon: `EmpImage`, 28x28, rounded corners (8pt via `CommonViewModel.corners`)
- App name: `EmpText`, primary color, 14pt, truncates tail
- Duration: `EmpText`, secondary color, 14pt, right-aligned
- Progress bar: `EmpProgressBar`, `progress = appDuration / totalDuration`, `fillColor = actionPrimary`, `barHeight = 4`
- Row height: ~80pt (icon row + progress bar + padding)
- Cell padding: `EmpSpacing.m` horizontal, `EmpSpacing.s` vertical
- Separator: 1pt line, `borderSubtle` color

### Footer
- "Show more..." button: `EmpButton.ghost`, centered
- Action: closes popover, opens DetailWindow

### Interactions
- Left click on row → tag assignment menu (NSMenu, preserved from current code)
- "Show more..." → opens Detail window

## Right-Click Menu (Status Bar Icon)

```
┌──────────────────────────────────┐
│  Подробно                         │  → opens DetailWindow
│  Синхронизация — 14:30            │  → triggers sync
│──────────────────────────────────│
│  Выйти                           │  → NSApp.terminate
└──────────────────────────────────┘
```

- Standard NSMenu on right-click of status bar icon
- Left-click → popover (unchanged)
- Sync item title format: "Синхронизация — HH:mm" or "Синхронизация — никогда"
- Clicking sync triggers sync and updates the timestamp

## Status Bar Click Handling

- Left click → toggle popover (current behavior)
- Right click → show NSMenu with 3 items

Implementation: override `mouseDown`/`rightMouseDown` on the status item button, or use `NSEvent` monitoring to distinguish click types.

## Files to Modify

| File | Action |
|------|--------|
| `TimelineViewController.swift` | Rewrite: remove segmented control, buttons, tag mode |
| `TimelineCellView.swift` | Rewrite: use EmpImage + EmpText + EmpProgressBar |
| `AppDelegate.swift` | Add right-click menu, update click handling |
| `TagCellView.swift` | Can be removed (no longer used in popover) |

## DS Components Used

- `EmpText` — date, total time, app name, duration, "Show more..."
- `EmpImage` — app icons (28x28, rounded corners)
- `EmpProgressBar` — duration proportion bar under each app
- `EmpButton` — "Show more..." ghost button
- `EmpSpacing` — consistent padding/margins
- `UIColor.Semantic` — textPrimary, textSecondary, borderSubtle, actionPrimary, backgroundPrimary

## No Missing DS Components

All needed primitives exist. Cell is assembled from existing components in app code.
