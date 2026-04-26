// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacUsageMeter",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "Shared",
            dependencies: [],
            path: "Shared"
        ),
        .executableTarget(
            name: "MacUsageMeter",
            dependencies: ["Shared"],
            path: "MacUsageMeter",
            exclude: [
                "App/Info.plist",
                "App/MacUsageMeter.entitlements"
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("CoreWLAN")
            ]
        ),
        .executableTarget(
            name: "Helper",
            dependencies: ["Shared"],
            path: "Helper",
            exclude: [
                "Info.plist",
                "Helper.entitlements",
                "Launchd.plist"
            ],
            linkerSettings: [
                .linkedFramework("CoreWLAN"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "XPCTestClient",
            dependencies: ["Shared"],
            path: "Tools",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "MacUsageMeterTests",
            dependencies: ["MacUsageMeter", "Shared"],
            path: "Tests/MacUsageMeterTests",
            exclude: ["Fixtures"]
        ),
        // NOTE: MacUsageMeterUITests is intentionally excluded from Package.swift.
        // XCUITests require an Xcode scheme with a host application and cannot run
        // via `swift test`. The test sources are kept in Tests/MacUsageMeterUITests/
        // for use when the project is opened in Xcode (via `open Package.swift`).
    ]
)
