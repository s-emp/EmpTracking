# Sync Status Indicator Design

## Problem

No visual feedback on whether sync succeeded or failed. The context menu shows sync time but not the result.

## Solution

Add emoji indicators next to sync time in the right-click context menu:
- `✅ Синхронизация — 14:32` (success)
- `❌ Синхронизация — 14:32` (failure)

## Approach: In-memory state (Approach A)

Store last sync result in `AppDelegate` as `lastSyncSuccess: Bool?`.

### Logic

- `SyncManager.onStatusChanged` updates the flag:
  - `.synced` -> `true`
  - `.error(...)` -> `false`
  - `.pending(count > 0)` -> `false`
  - `.idle`, `.syncing` -> no change
- `updateSyncMenuTitle()` prepends emoji based on flag value
- `nil` (before first sync) -> no emoji

### Display format

| State | Example |
|-------|---------|
| Before first sync | `Синхронизация — никогда` |
| Success | `✅ Синхронизация — 14:32` |
| Error/pending | `❌ Синхронизация — 14:32` |

### Files changed

- `Sources/AppDelegate.swift` (~10 lines)

### Trade-offs

- Status resets on app restart (acceptable: first sync happens 5s after launch)
- No DB changes needed
- Minimal code footprint
