// swift-tools-version: 6.0

import PackageDescription

let concurrencySettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "OracleOS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "OracleOS", targets: ["OracleOS"]),
        .library(name: "OracleControllerShared", targets: ["OracleControllerShared"]),
        .executable(name: "oracle", targets: ["oracle"]),
        .executable(name: "OracleControllerHost", targets: ["OracleControllerHost"]),
        .executable(name: "OracleController", targets: ["OracleController"]),
    ],
    dependencies: [
        // Pin AXorcist to a vendored revision.
        // The v0.1.0 tag bumped swift-tools-version to 6.2 which is
        // incompatible with this package's 6.0 toolchain.
        .package(path: "Vendor/AXorcist"),
        // This environment's SwiftPM test path needs an explicit Testing package
        // to satisfy Swift Testing dependencies under xcrun.
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.4"),
    ],
    targets: [
        .target(
            name: "OracleOS",
            dependencies: [
                .product(name: "AXorcist", package: "AXorcist")
            ],
            path: "Sources/OracleOS",
            exclude: ["Persistence/README.md"],
            swiftSettings: concurrencySettings,
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        .target(
            name: "OracleControllerShared",
            path: "Sources/OracleControllerShared",
            swiftSettings: concurrencySettings
        ),
        .executableTarget(
            name: "oracle",
            dependencies: ["OracleOS"],
            path: "Sources/oracle",
            swiftSettings: concurrencySettings
        ),
        .executableTarget(
            name: "OracleControllerHost",
            dependencies: ["OracleOS", "OracleControllerShared"],
            path: "Sources/OracleControllerHost",
            swiftSettings: concurrencySettings,
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .executableTarget(
            name: "OracleController",
            dependencies: ["OracleControllerShared", "OracleOS"],
            path: "Sources/OracleController",
            swiftSettings: concurrencySettings,
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .testTarget(
            name: "OracleOSTests",
            dependencies: [
                "OracleOS",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/OracleOSTests",
            exclude: ["Fixtures"],
            swiftSettings: concurrencySettings
        ),
        .testTarget(
            name: "OracleOSEvals",
            dependencies: [
                "OracleOS",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/OracleOSEvals",
            exclude: ["README.md"],
            swiftSettings: concurrencySettings
        ),
        .testTarget(
            name: "OracleControllerTests",
            dependencies: [
                "OracleController",
                "OracleControllerHost",
                "OracleControllerShared",
                "OracleOS",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/OracleControllerTests",
            swiftSettings: concurrencySettings
        ),
    ]
)
