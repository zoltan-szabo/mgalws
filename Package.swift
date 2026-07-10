// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "mgalcli",
    products: [
        .library(name: "mgalcliCore", targets: ["mgalcliCore"]),
    ],
    targets: [
        .executableTarget(
            name: "mgalcli",
            dependencies: ["mgalcliCore"],
            path: "Sources/mgalcli"
        ),
        .target(
            name: "mgalcliCore",
            path: "Sources/mgalcliCore"
        ),
        .testTarget(
            name: "mgalcliTests",
            dependencies: ["mgalcliCore"],
            path: "Tests/mgalcliTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
