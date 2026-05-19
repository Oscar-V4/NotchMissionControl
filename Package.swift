// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Roundy",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "NotchMissionControl",
            targets: ["NotchMissionControl"]
        )
    ],
    targets: [
        .executableTarget(
            name: "NotchMissionControl"
        )
    ]
)
