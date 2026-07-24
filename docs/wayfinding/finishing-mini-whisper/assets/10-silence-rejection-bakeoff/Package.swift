// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SilenceBakeoffTranscriber",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "FluidAudio", path: ".artifacts/FluidAudio")
    ],
    targets: [
        .executableTarget(
            name: "SilenceBakeoffTranscriber",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        )
    ]
)
