// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OhbeePreview",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OhbeeStage2Core", targets: ["OhbeeStage2Core"]),
        .executable(name: "OhbeePreview", targets: ["OhbeePreview"])
    ],
    targets: [
        .target(name: "OhbeeStage2Core"),
        .executableTarget(
            name: "OhbeePreview",
            dependencies: ["OhbeeStage2Core"]
        ),
        .testTarget(
            name: "OhbeeStage2CoreTests",
            dependencies: ["OhbeeStage2Core"]
        )
    ]
)

