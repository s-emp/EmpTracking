# Tuist Migration Design

**Goal:** Migrate EmpTracking from .xcodeproj to Tuist for declarative, reproducible project configuration.

**Scope:** Client app only (EmpTracking, EmpTrackingTests, EmpTrackingUITests). Server stays as a standalone Swift Package.

**Approach:** Migration with restructuring — rename source directories to Tuist conventions.

---

## Directory Structure

### Before

```
EmpTracking/                    # App sources
EmpTrackingTests/               # Unit tests
EmpTrackingUITests/             # UI tests
EmpTracking.xcodeproj/          # Xcode project (manual)
EmpTrackingServer/              # Server (unchanged)
docs/                           # Docs (unchanged)
```

### After

```
Sources/                        # App sources (renamed from EmpTracking/)
Tests/                          # Unit tests (renamed from EmpTrackingTests/)
UITests/                        # UI tests (renamed from EmpTrackingUITests/)
Project.swift                   # Tuist project definition
Tuist.swift                     # Tuist import
Tuist/
  Package.swift                 # External SPM dependencies
EmpTrackingServer/              # Server (unchanged)
docs/                           # Docs (unchanged)
```

`.xcodeproj` is deleted and added to `.gitignore` — Tuist generates it via `tuist generate`.

---

## Project.swift

Three targets replicating current configuration:

### EmpTracking (macOS App)
- **Bundle ID:** `com.emp.s.EmpTracking`
- **Sources:** `Sources/**`
- **Resources:** `Sources/Assets.xcassets`, `Sources/AppIcon.icon/**`, `Sources/Base.lproj/**`
- **Dependencies:** `EmpUI_macOS` (external SPM via GitHub)
- **Key settings:**
  - `LSUIElement: true` (menu bar app)
  - `ENABLE_APP_SANDBOX: NO`
  - `ENABLE_HARDENED_RUNTIME: YES`
  - `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`
  - `SWIFT_APPROACHABLE_CONCURRENCY: YES`
  - Accessibility usage description

### EmpTrackingTests (Unit Tests)
- **Sources:** `Tests/**`
- **Dependencies:** EmpTracking target, SnapshotTesting (external)

### EmpTrackingUITests (UI Tests)
- **Sources:** `UITests/**`
- **Dependencies:** EmpTracking target

### Global Settings
- Swift 5.0, macOS 14.0 deployment target
- Development team: VABTQXHL78, automatic code signing
- Debug + Release configurations

---

## Dependencies (Tuist/Package.swift)

| Dependency | URL | Version |
|---|---|---|
| EmpDesignSystem (EmpUI_macOS) | https://github.com/s-emp/EmpDesignSystem | >= 0.1.0 |
| swift-snapshot-testing (SnapshotTesting) | https://github.com/pointfreeco/swift-snapshot-testing | >= 1.17.0 |

---

## Deploy Script

Updated to use Tuist commands:
1. `pkill -x EmpTracking` — kill running instance
2. `tuist install` — resolve SPM dependencies
3. `tuist generate` — generate .xcodeproj
4. `tuist build -- -configuration Release` — build
5. Copy to `/Applications/`, relaunch

---

## .gitignore Additions

```
*.xcodeproj
*.xcworkspace
Derived/
Tuist/.build/
```

---

## What Does NOT Change

- `EmpTrackingServer/` — stays as standalone Swift Package
- `docs/` — stays as is
- Source code contents — only directory names change
- EmpDesignSystem connection method — stays as SPM via GitHub URL
