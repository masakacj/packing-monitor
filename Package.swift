// swift-tools-version: 5.3

import PackageDescription

let package = Package(
    name: "PackingMonitor",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .executable(name: "PackingMonitor", targets: ["PackingMonitor"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PackingMonitor",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("Network")
            ]
        )
    ]
)
