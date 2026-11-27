// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoltGuard",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "VoltGuardDomain", targets: ["VoltGuardDomain"]),
        .library(name: "VoltGuardData", targets: ["VoltGuardData"]),
        .executable(name: "VoltGuard", targets: ["VoltGuardApp"]),
        .executable(name: "voltguard-helper", targets: ["VoltGuardHelper"])
    ],
    targets: [
        .target(
            name: "VoltGuardDomain",
            dependencies: [],
            path: "Sources/VoltGuardDomain"
        ),
        .target(
            name: "VoltGuardData",
            dependencies: ["VoltGuardDomain"],
            path: "Sources/VoltGuardData",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "VoltGuardHelper",
            dependencies: [],
            path: "Sources/VoltGuardHelper",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "VoltGuardApp",
            dependencies: ["VoltGuardDomain", "VoltGuardData"],
            path: "Sources/VoltGuardApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppIntents")
            ]
        ),
        .testTarget(
            name: "VoltGuardTests",
            dependencies: ["VoltGuardDomain", "VoltGuardData", "VoltGuardApp"],
            path: "Tests/VoltGuardTests"
        )
    ]
)
