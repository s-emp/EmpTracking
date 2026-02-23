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
