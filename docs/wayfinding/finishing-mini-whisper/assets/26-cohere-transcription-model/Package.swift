// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CohereTranscriptionHarness",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            name: "FluidAudio",
            path: ".artifacts/FluidAudio"
        )
    ],
    targets: [
        .executableTarget(
            name: "CohereTranscriptionHarness",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        )
    ]
)
