// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BlackHoleMetal",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "BlackHoleMetal",
            path: "Sources/BlackHoleMetal",
            resources: [
                .copy("Shaders/geodesic.metal"),
                .copy("Shaders/grid.metal"),
                .copy("Shaders/quad.metal")
            ]
        )
    ]
)
