// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FluidAudioHarness",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            name: "FluidAudio",
            path: "../../.artifacts/FluidAudio"
        )
    ],
    targets: [
        .executableTarget(
            name: "FluidAudioHarness",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        )
    ]
)
