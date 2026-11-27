// swift-tools-version:6.0
import PackageDescription

// StatsCore (model layer) builds everywhere, so its tests also run on Linux.
// StatsKit (data layer) and MacStats (UI layer) are macOS only.
var products: [Product] = [
    .library(name: "StatsCore", targets: ["StatsCore"]),
]

var targets: [Target] = [
    .target(
        name: "StatsCore",
        path: "Sources/StatsCore"
    ),
    .testTarget(
        name: "StatsCoreTests",
        dependencies: ["StatsCore"],
        path: "Tests/StatsCoreTests"
    ),
]

#if os(macOS)
products.append(.executable(name: "MacStats", targets: ["MacStats"]))
targets += [
    .target(
        name: "StatsKit",
        dependencies: ["StatsCore"],
        path: "Sources/StatsKit",
        swiftSettings: [
            .swiftLanguageMode(.v5),
            .enableUpcomingFeature("StrictConcurrency"),
        ],
        linkerSettings: [
            .linkedLibrary("sqlite3"),
            .linkedFramework("IOKit"),
        ]
    ),
    .executableTarget(
        name: "MacStats",
        dependencies: ["StatsCore", "StatsKit"],
        path: "Sources/MacStats",
        swiftSettings: [
            .swiftLanguageMode(.v5),
            .enableUpcomingFeature("StrictConcurrency"),
        ],
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("SwiftUI"),
            .linkedFramework("Charts"),
            .linkedFramework("ServiceManagement"),
        ]
    ),
]
#endif

let package = Package(
    name: "MacStats",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
