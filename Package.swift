// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "PackingMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PackingMonitor", targets: ["PackingMonitor"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/hummingbird-project/hummingbird.git",
            from: "2.26.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "PackingMonitor",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreMedia")
            ]
        )
    ]
)
