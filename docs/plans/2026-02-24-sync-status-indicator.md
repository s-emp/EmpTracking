# Sync Status Indicator Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Show sync success/failure emoji (✅/❌) next to sync time in the right-click context menu.

**Architecture:** Add an in-memory `lastSyncSuccess: Bool?` property to `AppDelegate`. Update it from `SyncManager.onStatusChanged` callback. Prepend emoji in `updateSyncMenuTitle()`.

**Tech Stack:** Swift, AppKit (NSMenuItem)

---

### Task 1: Add lastSyncSuccess property and update it from sync callback

**Files:**
- Modify: `Sources/AppDelegate.swift:10` (add property after `syncManager` declaration)
- Modify: `Sources/AppDelegate.swift:85-100` (update `setupSync()` method)

**Step 1: Add property to AppDelegate**

After line 10 (`private var syncManager: SyncManager?`), add:

```swift
private var lastSyncSuccess: Bool?
```

**Step 2: Update `onStatusChanged` callback in `setupSync()`**

Replace the current `onStatusChanged` block (lines 93-95):

```swift
syncManager?.onStatusChanged = { (_: SyncManager.SyncStatus) in
    // Status display removed from popover in redesign
}
```

With:

```swift
syncManager?.onStatusChanged = { [weak self] status in
    switch status {
    case .synced:
        self?.lastSyncSuccess = true
    case .error:
        self?.lastSyncSuccess = false
    case .pending(let count) where count > 0:
        self?.lastSyncSuccess = false
    default:
        break
    }
}
```

**Step 3: Verify it compiles**

Run: `cd /Users/emp15/Developer/EmpTracking && tuist generate && xcodebuild -scheme EmpTracking -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

---

### Task 2: Update menu title to include emoji

**Files:**
- Modify: `Sources/AppDelegate.swift:177-187` (update `updateSyncMenuTitle()` method)

**Step 1: Update `updateSyncMenuTitle()` to prepend emoji**

Replace the current method (lines 177-187):

```swift
private func updateSyncMenuTitle() {
    let lastPullTime = try? db.fetchSetting(key: "last_pull_time")
    if let timeStr = lastPullTime, let timestamp = TimeInterval(timeStr) {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        syncMenuItem.title = "Синхронизация — \(formatter.string(from: date))"
    } else {
        syncMenuItem.title = "Синхронизация — никогда"
    }
}
```

With:

```swift
private func updateSyncMenuTitle() {
    let prefix: String
    switch lastSyncSuccess {
    case .some(true): prefix = "✅ "
    case .some(false): prefix = "❌ "
    case .none: prefix = ""
    }

    let lastPullTime = try? db.fetchSetting(key: "last_pull_time")
    if let timeStr = lastPullTime, let timestamp = TimeInterval(timeStr) {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        syncMenuItem.title = "\(prefix)Синхронизация — \(formatter.string(from: date))"
    } else {
        syncMenuItem.title = "\(prefix)Синхронизация — никогда"
    }
}
```

**Step 2: Build and verify**

Run: `cd /Users/emp15/Developer/EmpTracking && xcodebuild -scheme EmpTracking -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

---

### Task 3: Manual QA

**Step 1: Build and run the app**

Run: `cd /Users/emp15/Developer/EmpTracking && xcodebuild -scheme EmpTracking -configuration Debug build 2>&1 | tail -5`

**Step 2: Right-click on status bar icon**

- Before first sync: should show `Синхронизация — никогда` (no emoji)
- After ~5 seconds (first sync): right-click again, should show `✅ Синхронизация — HH:mm`
- To test failure: disconnect from network or stop server, wait 60s, right-click — should show `❌ Синхронизация — HH:mm`
