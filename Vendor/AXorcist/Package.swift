// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
// NOTE: This vendored package is stripped to library-only for Oracle-OS.
// The axorc executable and tests are not built from the root package.

import PackageDescription

let package = Package(
    name: "AXorcist",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "AXorcist", targets: ["AXorcist"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AXorcist",
            path: "Sources/AXorcist"
        )
    ]
)