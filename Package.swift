// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "mgalws",
    products: [
        .library(name: "mgalwsCore", targets: ["mgalwsCore"]),
    ],
    targets: [
        .executableTarget(
            name: "mgalws",
            dependencies: ["mgalwsCore"],
            path: "Sources/mgalws"
        ),
        .target(
            name: "mgalwsCore",
            path: "Sources/mgalwsCore"
        ),
        .testTarget(
            name: "mgalwsTests",
            dependencies: ["mgalwsCore"],
            path: "Tests/mgalwsTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
