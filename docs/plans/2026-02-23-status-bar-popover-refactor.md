# Status Bar Popover Refactor — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor the status bar popover to match Figma design using EmpDesignSystem components, add right-click NSMenu on status bar icon.

**Architecture:** Rewrite TimelineViewController and TimelineCellView from scratch using EmpDesignSystem components (EmpText, EmpImage, EmpProgressBar, EmpButton). Add NSMenu for right-click on status bar icon. Remove segmented control, bottom buttons, and tags mode from popover.

**Tech Stack:** AppKit, EmpUI_macOS framework (EmpDesignSystem)

---

### Task 0: Add EmpUI_macOS framework to EmpTracking project

The EmpDesignSystem is a Tuist project at `../EmpDesignSystem`. EmpUI_macOS is a framework target. EmpTracking is a plain `.xcodeproj`. We need to link the built framework.

**Files:**
- Modify: `EmpTracking.xcodeproj/project.pbxproj` (via Xcode CLI)

**Step 1: Build EmpUI_macOS framework**

Run:
```bash
cd /Users/emp15/Developer/EmpDesignSystem && tuist generate && xcodebuild -workspace EmpDesignSystem.xcworkspace -scheme EmpUI_macOS -configuration Release -derivedDataPath .build ONLY_ACTIVE_ARCH=NO
```
Expected: BUILD SUCCEEDED

**Step 2: Copy framework sources into EmpTracking**

Since this is a macOS app without SPM, the simplest approach is to add the EmpUI_macOS source files directly to the EmpTracking project. Copy the source files:

```bash
mkdir -p /Users/emp15/Developer/EmpTracking/EmpTracking/DesignSystem
cp -R /Users/emp15/Developer/EmpDesignSystem/EmpUI_macOS/Sources/Common/* /Users/emp15/Developer/EmpTracking/EmpTracking/DesignSystem/
cp -R /Users/emp15/Developer/EmpDesignSystem/EmpUI_macOS/Sources/Components/* /Users/emp15/Developer/EmpTracking/EmpTracking/DesignSystem/
```

**Step 3: Add files to Xcode project**

Add all `.swift` files from `EmpTracking/DesignSystem/` to the Xcode project target `EmpTracking`.

**Step 4: Verify it builds**

Run:
```bash
xcodebuild -project /Users/emp15/Developer/EmpTracking/EmpTracking.xcodeproj -scheme EmpTracking -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add -A EmpTracking/DesignSystem/
git commit -m "feat: add EmpUI_macOS design system sources"
```

---

### Task 1: Rewrite TimelineCellView with DS components

**Files:**
- Modify: `EmpTracking/Views/TimelineCellView.swift`

**Step 1: Rewrite TimelineCellView**

Replace the entire contents of `TimelineCellView.swift`:

```swift
import Cocoa

final class TimelineCellView: NSTableCellView {
    private let iconImage = EmpImage()
    private let titleText = EmpText()
    private let durationText = EmpText()
    private let progressBar = EmpProgressBar()
    private let separator = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        iconImage.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconImage)

        titleText.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleText)

        durationText.translatesAutoresizingMaskIntoConstraints = false
        durationText.setContentHuggingPriority(.required, for: .horizontal)
        durationText.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(durationText)

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressBar)

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.Semantic.borderSubtle.cgColor
        addSubview(separator)

        let hPad = EmpSpacing.m.rawValue  // 16
        let vPad = EmpSpacing.s.rawValue  // 12

        NSLayoutConstraint.activate([
            // Icon: 28x28 with rounded corners, vertically centered in top row area
            iconImage.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPad),
            iconImage.topAnchor.constraint(equalTo: topAnchor, constant: vPad),
            iconImage.widthAnchor.constraint(equalToConstant: 28),
            iconImage.heightAnchor.constraint(equalToConstant: 28),

            // Title: next to icon, centered with icon
            titleText.leadingAnchor.constraint(equalTo: iconImage.trailingAnchor, constant: EmpSpacing.s.rawValue),
            titleText.centerYAnchor.constraint(equalTo: iconImage.centerYAnchor),
            titleText.trailingAnchor.constraint(lessThanOrEqualTo: durationText.leadingAnchor, constant: -EmpSpacing.xs.rawValue),

            // Duration: right-aligned, centered with icon
            durationText.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPad),
            durationText.centerYAnchor.constraint(equalTo: iconImage.centerYAnchor),

            // Progress bar: below icon row, full width with padding
            progressBar.topAnchor.constraint(equalTo: iconImage.bottomAnchor, constant: EmpSpacing.xs.rawValue),
            progressBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPad),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPad),

            // Separator: at bottom
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPad),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPad),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    func configure(summary: AppSummary, totalDuration: TimeInterval) {
        let appIcon = summary.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: "App")!

        iconImage.configure(with: EmpImage.ViewModel(
            common: CommonViewModel(corners: .init(radius: 8)),
            image: appIcon,
            size: CGSize(width: 28, height: 28),
            contentMode: .aspectFit
        ))

        titleText.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: summary.appName,
                font: .systemFont(ofSize: 14, weight: .medium),
                color: NSColor.Semantic.textPrimary
            )),
            numberOfLines: 1
        ))

        let total = Int(summary.totalDuration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let durationString = hours > 0 ? "\(hours)h \(minutes)min" : "\(minutes)min"

        durationText.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: durationString,
                font: .systemFont(ofSize: 14),
                color: NSColor.Semantic.textSecondary
            )),
            numberOfLines: 1,
            alignment: .right
        ))

        let progress = totalDuration > 0 ? CGFloat(summary.totalDuration / totalDuration) : 0
        progressBar.configure(with: EmpProgressBar.ViewModel(
            progress: progress,
            fillColor: NSColor.Semantic.actionPrimary,
            barHeight: 4
        ))
    }
}
```

**Step 2: Verify it builds**

Run:
```bash
xcodebuild -project /Users/emp15/Developer/EmpTracking/EmpTracking.xcodeproj -scheme EmpTracking -configuration Debug build 2>&1 | tail -5
```
Expected: Build may fail because TimelineViewController still calls `configure(summary:)` without `totalDuration`. This is expected — we'll fix it in Task 2.

**Step 3: Commit**

```bash
git add EmpTracking/Views/TimelineCellView.swift
git commit -m "feat: rewrite TimelineCellView with EmpDesignSystem components"
```

---

### Task 2: Rewrite TimelineViewController

**Files:**
- Modify: `EmpTracking/Views/TimelineViewController.swift`

**Step 1: Rewrite TimelineViewController**

Replace the entire contents of `TimelineViewController.swift`:

```swift
import Cocoa

final class TimelineViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let db: DatabaseManager
    private var appSummaries: [AppSummary] = []
    private var totalDuration: TimeInterval = 0
    var onDetail: (() -> Void)?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let dateText = EmpText()
    private let totalText = EmpText()
    private let headerSeparator = NSView()
    private let showMoreButton = EmpButton()

    init(db: DatabaseManager) {
        self.db = db
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        self.view = container

        let hPad = EmpSpacing.m.rawValue

        // Date label (left)
        dateText.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(dateText)

        // Total label (right)
        totalText.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(totalText)

        // Header separator
        headerSeparator.translatesAutoresizingMaskIntoConstraints = false
        headerSeparator.wantsLayer = true
        headerSeparator.layer?.backgroundColor = NSColor.Semantic.borderSubtle.cgColor
        container.addSubview(headerSeparator)

        // Table
        let column = NSTableColumn(identifier: .init("activity"))
        column.title = ""
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 72
        tableView.style = .plain
        tableView.selectionHighlightStyle = .none

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        tableView.backgroundColor = .clear
        container.addSubview(scrollView)

        // "Show more..." button
        showMoreButton.translatesAutoresizingMaskIntoConstraints = false
        showMoreButton.configure(with: EmpButton.Preset.ghost(
            .primary,
            content: .init(center: .text("Show more...")),
            size: .small
        ))
        showMoreButton.action = { [weak self] in
            self?.onDetail?()
        }
        container.addSubview(showMoreButton)

        NSLayoutConstraint.activate([
            // Header
            dateText.topAnchor.constraint(equalTo: container.topAnchor, constant: hPad),
            dateText.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hPad),

            totalText.centerYAnchor.constraint(equalTo: dateText.centerYAnchor),
            totalText.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -hPad),

            // Header separator
            headerSeparator.topAnchor.constraint(equalTo: dateText.bottomAnchor, constant: EmpSpacing.s.rawValue),
            headerSeparator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hPad),
            headerSeparator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -hPad),
            headerSeparator.heightAnchor.constraint(equalToConstant: 1),

            // Table
            scrollView.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: showMoreButton.topAnchor, constant: -EmpSpacing.xs.rawValue),

            // Footer button
            showMoreButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            showMoreButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -EmpSpacing.s.rawValue),
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
    }

    func reload() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM d"
        let dateString = formatter.string(from: Date())

        dateText.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: dateString,
                font: .systemFont(ofSize: 14),
                color: NSColor.Semantic.textSecondary
            )),
            numberOfLines: 1
        ))

        let since = Calendar.current.startOfDay(for: Date())

        do {
            appSummaries = try db.fetchAppSummaries(since: since)
            totalDuration = appSummaries.reduce(0.0) { $0 + $1.totalDuration }
        } catch {
            print("Error fetching summaries: \(error)")
        }

        let totalString = formatDuration(totalDuration)
        totalText.configure(with: EmpText.ViewModel(
            content: .plain(.init(
                text: totalString,
                font: .systemFont(ofSize: 16, weight: .bold),
                color: NSColor.Semantic.textPrimary
            )),
            numberOfLines: 1,
            alignment: .right
        ))

        tableView.reloadData()
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)h \(minutes)min"
    }

    // MARK: - NSTableViewDataSource

    nonisolated func numberOfRows(in tableView: NSTableView) -> Int {
        MainActor.assumeIsolated {
            return appSummaries.count
        }
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("TimelineCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? TimelineCellView)
            ?? TimelineCellView()
        cell.identifier = id
        cell.configure(summary: appSummaries[row], totalDuration: totalDuration)
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        let summary = appSummaries[row]
        showTagMenu(forAppId: summary.appId, at: row)
        return false
    }

    // MARK: - Tag Menu (preserved from current code)

    private func showTagMenu(forAppId appId: Int64, at row: Int) {
        let menu = NSMenu()

        let tags: [Tag]
        let appInfo: AppInfo?
        do {
            tags = try db.fetchAllTags()
            appInfo = try db.fetchAppInfo(appId: appId)
        } catch {
            print("Error loading tags: \(error)")
            return
        }

        let currentTagId = appInfo?.defaultTagId

        let noTagItem = NSMenuItem(title: "Без тега", action: #selector(tagMenuItemClicked(_:)), keyEquivalent: "")
        noTagItem.target = self
        noTagItem.representedObject = ["appId": appId, "tagId": NSNull()] as NSDictionary
        if currentTagId == nil { noTagItem.state = .on }
        menu.addItem(noTagItem)

        if !tags.isEmpty {
            menu.addItem(.separator())
        }

        for tag in tags {
            let item = NSMenuItem(title: tag.name, action: #selector(tagMenuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["appId": appId, "tagId": tag.id] as NSDictionary
            if currentTagId == tag.id { item.state = .on }

            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let color = NSColor(hex: isDark ? tag.colorDark : tag.colorLight)
            let dot = NSAttributedString(string: "● ", attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 13)])
            let name = NSAttributedString(string: tag.name, attributes: [.font: NSFont.systemFont(ofSize: 13)])
            let title = NSMutableAttributedString()
            title.append(dot)
            title.append(name)
            item.attributedTitle = title

            menu.addItem(item)
        }

        menu.addItem(.separator())

        let createItem = NSMenuItem(title: "Создать тег...", action: #selector(createTagClicked(_:)), keyEquivalent: "")
        createItem.target = self
        menu.addItem(createItem)

        let rect = tableView.rect(ofRow: row)
        menu.popUp(positioning: nil, at: NSPoint(x: rect.midX, y: rect.midY), in: tableView)
    }

    @objc private func tagMenuItemClicked(_ sender: NSMenuItem) {
        guard let dict = sender.representedObject as? NSDictionary,
              let appId = dict["appId"] as? Int64 else { return }
        let tagId = dict["tagId"] as? Int64
        do {
            try db.setDefaultTag(appId: appId, tagId: tagId)
            reload()
        } catch {
            print("Error setting tag: \(error)")
        }
    }

    @objc private func createTagClicked(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Создать тег"
        alert.addButton(withTitle: "Создать")
        alert.addButton(withTitle: "Отмена")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))

        let nameField = NSTextField(frame: NSRect(x: 0, y: 70, width: 300, height: 24))
        nameField.placeholderString = "Название тега"
        container.addSubview(nameField)

        let lightLabel = NSTextField(labelWithString: "Светлая:")
        lightLabel.frame = NSRect(x: 0, y: 35, width: 60, height: 20)
        container.addSubview(lightLabel)

        let lightColorWell = NSColorWell(frame: NSRect(x: 65, y: 30, width: 50, height: 30))
        lightColorWell.color = .systemGreen
        container.addSubview(lightColorWell)

        let darkLabel = NSTextField(labelWithString: "Тёмная:")
        darkLabel.frame = NSRect(x: 150, y: 35, width: 60, height: 20)
        container.addSubview(darkLabel)

        let darkColorWell = NSColorWell(frame: NSRect(x: 215, y: 30, width: 50, height: 30))
        darkColorWell.color = .systemGreen
        container.addSubview(darkColorWell)

        alert.accessoryView = container

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        do {
            _ = try db.createTag(name: name, colorLight: lightColorWell.color.hexString, colorDark: darkColorWell.color.hexString)
            reload()
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Ошибка"
            errorAlert.informativeText = "Тег с таким именем уже существует."
            errorAlert.runModal()
        }
    }
}
```

**Step 2: Verify it builds**

Run:
```bash
xcodebuild -project /Users/emp15/Developer/EmpTracking/EmpTracking.xcodeproj -scheme EmpTracking -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED (may need to fix small compilation issues)

**Step 3: Commit**

```bash
git add EmpTracking/Views/TimelineViewController.swift
git commit -m "feat: rewrite TimelineViewController with DS components, remove buttons/segmented control"
```

---

### Task 3: Add right-click NSMenu to status bar icon

**Files:**
- Modify: `EmpTracking/AppDelegate.swift`

**Step 1: Update AppDelegate**

Changes to `AppDelegate.swift`:

1. Add `private var statusMenu: NSMenu!` property
2. Add `private var syncMenuItem: NSMenuItem!` property
3. Create `setupStatusMenu()` method that builds the NSMenu
4. Modify `setupMenubar()` to set up right-click handling via `sendAction(on:)` and event monitoring
5. Remove `updateSyncStatus` calls to TimelineViewController (no longer needed there)
6. Add `updateSyncMenuTitle()` method that reads `last_pull_time` from DB

The key approach for distinguishing left/right click on NSStatusItem:
- Use `button.sendAction(on: [.leftMouseUp, .rightMouseUp])`
- In the action handler, check `NSApp.currentEvent?.type`

```swift
// In setupMenubar(), replace:
//   button.target = self
//   button.action = #selector(togglePopover)
// With:
button.target = self
button.action = #selector(statusItemClicked)
button.sendAction(on: [.leftMouseUp, .rightMouseUp])

// New method:
@objc private func statusItemClicked() {
    guard let event = NSApp.currentEvent else { return }
    if event.type == .rightMouseUp {
        updateSyncMenuTitle()
        statusItem.menu = statusMenu
        statusItem.button?.performClick(nil)
        // Reset menu so left-click works normally next time
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    } else {
        togglePopover()
    }
}
```

The `setupStatusMenu()`:
```swift
private func setupStatusMenu() {
    statusMenu = NSMenu()

    let detailItem = NSMenuItem(title: "Подробно", action: #selector(showDetailFromMenu), keyEquivalent: "")
    detailItem.target = self
    statusMenu.addItem(detailItem)

    syncMenuItem = NSMenuItem(title: "Синхронизация", action: #selector(syncFromMenu), keyEquivalent: "")
    syncMenuItem.target = self
    statusMenu.addItem(syncMenuItem)

    statusMenu.addItem(.separator())

    let quitItem = NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    statusMenu.addItem(quitItem)
}

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

@objc private func showDetailFromMenu() {
    showDetailWindow()
}

@objc private func syncFromMenu() {
    syncManager?.performManualSync()
}
```

Note: `performManualSync()` may need to be added to SyncManager if it doesn't exist — check if `performSync()` is private and expose a public method.

**Step 2: Remove `updateSyncStatus` from TimelineViewController**

The `updateSyncStatus` method and `syncButton` are removed in Task 2. Also remove the call in `AppDelegate.togglePopover()` and `setupSync()`.

In `togglePopover()`, remove:
```swift
if let status = syncManager?.syncStatus {
    timelineVC.updateSyncStatus(status)
}
```

In `setupSync()`, remove:
```swift
syncManager?.onStatusChanged = { [weak self] (status: SyncManager.SyncStatus) in
    self?.timelineVC.updateSyncStatus(status)
}
```

**Step 3: Verify it builds**

Run:
```bash
xcodebuild -project /Users/emp15/Developer/EmpTracking/EmpTracking.xcodeproj -scheme EmpTracking -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add EmpTracking/AppDelegate.swift
git commit -m "feat: add right-click context menu on status bar icon"
```

---

### Task 4: Verify SyncManager has public sync method

**Files:**
- Modify (if needed): `EmpTracking/Services/SyncManager.swift`

**Step 1: Check if performSync is accessible**

The current `performSync()` is private. We need a public trigger for the menu item.

Add to `SyncManager`:
```swift
func syncNow() {
    performSync()
}
```

**Step 2: Update AppDelegate to use it**

In `syncFromMenu()`, call `syncManager?.syncNow()`.

**Step 3: Verify it builds**

Run:
```bash
xcodebuild -project /Users/emp15/Developer/EmpTracking/EmpTracking.xcodeproj -scheme EmpTracking -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add EmpTracking/Services/SyncManager.swift EmpTracking/AppDelegate.swift
git commit -m "feat: expose syncNow() for manual sync trigger"
```

---

### Task 5: Build, run, and verify visually

**Step 1: Build and run**

Run:
```bash
xcodebuild -project /Users/emp15/Developer/EmpTracking/EmpTracking.xcodeproj -scheme EmpTracking -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 2: Manual visual check**

- Launch the app
- Click status bar icon → popover should show:
  - Header with date (left) and total time (right, bold)
  - Separator
  - App rows with icon (rounded), name, duration, progress bar
  - "Show more..." button at bottom
- Right-click status bar icon → NSMenu with "Подробно", "Синхронизация — HH:mm", separator, "Выйти"
- Click "Show more..." → Detail window opens
- Click on app row → tag menu appears

**Step 3: Fix any visual issues found**

Adjust spacing, fonts, or colors as needed to match Figma.

**Step 4: Final commit**

```bash
git add -A
git commit -m "fix: visual adjustments for popover layout"
```
