# Tuist Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate EmpTracking from .xcodeproj to Tuist with directory restructuring.

**Architecture:** Create `Project.swift` + `Tuist/Package.swift` defining 3 targets (app, unit tests, UI tests). Rename source directories to Tuist conventions (`Sources/`, `Tests/`, `UITests/`). Delete old `.xcodeproj`. EmpDesignSystem stays as external SPM dependency via GitHub URL.

**Tech Stack:** Tuist 4.131.1 (installed via mise), Swift 5.0, macOS 14.0+

---

### Task 0: Create feature branch

**Step 1: Create and switch to branch**

```bash
cd /Users/emp15/Developer/EmpTracking
git checkout -b feature/tuist-migration
```

**Step 2: Verify**

```bash
git branch --show-current
```

Expected: `feature/tuist-migration`

---

### Task 1: Create Tuist configuration files

**Files:**
- Create: `Tuist.swift`
- Create: `Tuist/Package.swift`
- Create: `Project.swift`

**Step 1: Create `Tuist.swift`**

```swift
import ProjectDescription

let tuist = Tuist(project: .tuist())
```

**Step 2: Create `Tuist/Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: [:]
)
#endif

let package = Package(
    name: "EmpTracking",
    dependencies: [
        .package(url: "https://github.com/s-emp/EmpDesignSystem", from: "0.1.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ]
)
```

**Step 3: Create `Project.swift`**

```swift
import ProjectDescription

let project = Project(
    name: "EmpTracking",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.0",
            "MACOSX_DEPLOYMENT_TARGET": "14.0",
            "DEVELOPMENT_TEAM": "VABTQXHL78",
            "CODE_SIGN_STYLE": "Automatic",
        ],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release"),
        ]
    ),
    targets: [
        .target(
            name: "EmpTracking",
            destinations: .macOS,
            product: .app,
            bundleId: "com.emp.s.EmpTracking",
            infoPlist: .extendingDefault(with: [
                "LSUIElement": true,
                "NSAccessibilityUsageDescription": "EmpTracking needs Accessibility access to read window titles of the active application.",
                "NSPrincipalClass": "NSApplication",
            ]),
            sources: ["Sources/**"],
            resources: [
                "Sources/Assets.xcassets",
                "Sources/AppIcon.icon/**",
                "Sources/Base.lproj/**",
            ],
            dependencies: [
                .external(name: "EmpUI_macOS"),
            ],
            settings: .settings(base: [
                "ENABLE_APP_SANDBOX": "NO",
                "ENABLE_HARDENED_RUNTIME": "YES",
                "COMBINE_HIDPI_IMAGES": "YES",
                "REGISTER_APP_GROUPS": "YES",
                "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
                "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
                "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
            ])
        ),
        .target(
            name: "EmpTrackingTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.emp.s.EmpTrackingTests",
            sources: ["Tests/**"],
            resources: ["Tests/__Snapshots__/**"],
            dependencies: [
                .target(name: "EmpTracking"),
                .external(name: "SnapshotTesting"),
            ]
        ),
        .target(
            name: "EmpTrackingUITests",
            destinations: .macOS,
            product: .uiTests,
            bundleId: "com.emp.s.EmpTrackingUITests",
            sources: ["UITests/**"],
            dependencies: [
                .target(name: "EmpTracking"),
            ]
        ),
    ]
)
```

**Step 4: Verify files exist**

```bash
ls -la /Users/emp15/Developer/EmpTracking/Tuist.swift \
      /Users/emp15/Developer/EmpTracking/Project.swift \
      /Users/emp15/Developer/EmpTracking/Tuist/Package.swift
```

Expected: All 3 files present.

**Step 5: Commit**

```bash
git add Tuist.swift Project.swift Tuist/Package.swift
git commit -m "feat: add Tuist configuration files"
```

---

### Task 2: Rename source directories

**Step 1: Rename `EmpTracking/` → `Sources/`**

```bash
cd /Users/emp15/Developer/EmpTracking
git mv EmpTracking Sources
```

**Step 2: Rename `EmpTrackingTests/` → `Tests/`**

```bash
git mv EmpTrackingTests Tests
```

**Step 3: Rename `EmpTrackingUITests/` → `UITests/`**

```bash
git mv EmpTrackingUITests UITests
```

**Step 4: Verify structure**

```bash
ls -d Sources Tests UITests
```

Expected: All 3 directories listed.

```bash
ls Sources/AppDelegate.swift Sources/Models Sources/Views Sources/Services
```

Expected: Files/dirs present inside Sources.

**Step 5: Commit**

```bash
git add -A
git commit -m "refactor: rename source directories for Tuist conventions"
```

---

### Task 3: Update .gitignore and delete .xcodeproj

**Step 1: Add Tuist entries to `.gitignore`**

Add these lines at the end of `/Users/emp15/Developer/EmpTracking/.gitignore`:

```
# Tuist
*.xcodeproj
*.xcworkspace
Derived/
Tuist/.build/
```

**Step 2: Remove .xcodeproj from git tracking**

```bash
cd /Users/emp15/Developer/EmpTracking
git rm -r EmpTracking.xcodeproj
```

**Step 3: Verify**

```bash
ls EmpTracking.xcodeproj 2>&1
```

Expected: `No such file or directory`

**Step 4: Commit**

```bash
git add .gitignore
git commit -m "chore: update gitignore for Tuist, remove xcodeproj"
```

---

### Task 4: Install dependencies and generate project

**Step 1: Install SPM dependencies**

```bash
cd /Users/emp15/Developer/EmpTracking
tuist install
```

Expected: Dependencies resolved successfully. Look for `EmpDesignSystem` and `swift-snapshot-testing` in output.

**Step 2: Generate Xcode project**

```bash
tuist generate
```

Expected: Project generated successfully. Xcode may open automatically.

**Step 3: Verify generated project**

```bash
ls EmpTracking.xcodeproj
```

Expected: Generated `.xcodeproj` exists (it's gitignored, so it won't be tracked).

---

### Task 5: Build and verify

**Step 1: Build Release**

```bash
cd /Users/emp15/Developer/EmpTracking
tuist build EmpTracking -- -configuration Release
```

Expected: `BUILD SUCCEEDED`

If build fails, check:
- Missing imports → source files may need `import EmpUI_macOS`
- Resource paths → adjust `resources:` in `Project.swift`
- Build settings → compare with original xcodeproj settings

**Step 2: Build Tests**

```bash
tuist build EmpTrackingTests
```

Expected: `BUILD SUCCEEDED`

**Step 3: Run tests**

```bash
tuist test EmpTrackingTests
```

Expected: All tests pass.

**Step 4: Deploy and verify app works**

```bash
pkill -x EmpTracking 2>/dev/null; sleep 1

BUILD_DIR=$(xcodebuild build \
  -project /Users/emp15/Developer/EmpTracking/EmpTracking.xcodeproj \
  -scheme EmpTracking \
  -destination 'platform=macOS' \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  -showBuildSettings 2>/dev/null | grep ' TARGET_BUILD_DIR' | xargs | cut -d= -f2 | xargs)

rm -rf /Applications/EmpTracking.app
cp -R "$BUILD_DIR/EmpTracking.app" /Applications/
open /Applications/EmpTracking.app
```

Expected: App launches, appears in menu bar, popover shows app usage data.

**Step 5: Commit (if any fixes were needed)**

```bash
git add -A
git commit -m "fix: adjust Tuist configuration for successful build"
```

---

### Task 6: Update deploy skill

**File:**
- Modify: `/Users/emp15/.claude/skills/deploy-emptracking/instructions.md`

**Step 1: Update deploy script to use Tuist**

Replace the deploy skill content with:

```markdown
# Deploy EmpTracking

Build the project using Tuist and replace the app in /Applications.

## Steps

1. Kill running instance (if any)
2. Generate project & build Release
3. Replace app in /Applications
4. Optionally relaunch

## Commands

\```bash
# 1. Kill running instance
pkill -x EmpTracking 2>/dev/null; sleep 1

# 2. Generate & build Release
cd /Users/emp15/Developer/EmpTracking
tuist install
tuist generate --no-open
tuist build EmpTracking -- -configuration Release CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E '(error:|BUILD)'

# 3. Find built app and replace in /Applications
BUILD_DIR=$(xcodebuild build \
  -project /Users/emp15/Developer/EmpTracking/EmpTracking.xcodeproj \
  -scheme EmpTracking \
  -destination 'platform=macOS' \
  -configuration Release \
  -showBuildSettings 2>/dev/null | grep ' TARGET_BUILD_DIR' | xargs | cut -d= -f2 | xargs)

rm -rf /Applications/EmpTracking.app
cp -R "$BUILD_DIR/EmpTracking.app" /Applications/

# 4. Relaunch
open /Applications/EmpTracking.app
\```

## Verification

After deploy, confirm:
- `ls /Applications/EmpTracking.app` exists
- App appears in menubar (clock icon)

## Common Issues

- **App won't quit**: Use `pkill -9 EmpTracking` if graceful kill fails
- **Build fails**: Run `tuist build EmpTracking` without grep for full errors
- **Dependencies outdated**: Run `tuist install` to refresh SPM dependencies
- **Project out of sync**: Run `tuist generate --no-open` to regenerate
```

**Step 2: Verify skill file is updated**

Read the file back to confirm contents are correct.

---

### Task 7: Final verification and cleanup

**Step 1: Verify project structure is clean**

```bash
cd /Users/emp15/Developer/EmpTracking
ls -la
```

Expected structure:
```
Sources/            # App sources
Tests/              # Unit tests
UITests/            # UI tests
EmpTrackingServer/  # Server (unchanged)
docs/               # Documentation
Project.swift       # Tuist project definition
Tuist.swift         # Tuist config
Tuist/              # Dependencies
.gitignore          # Updated
README.md           # Unchanged
```

No `EmpTracking.xcodeproj` in git (may exist locally as generated, but gitignored).

**Step 2: Verify git status is clean**

```bash
git status
```

Expected: Clean working tree (or only generated/ignored files).

**Step 3: Full rebuild from scratch**

```bash
# Clean and rebuild
rm -rf EmpTracking.xcodeproj
rm -rf Derived
tuist clean
tuist install
tuist generate --no-open
tuist build EmpTracking -- -configuration Release
```

Expected: `BUILD SUCCEEDED` — confirms the project can be built from scratch with just Tuist files.
