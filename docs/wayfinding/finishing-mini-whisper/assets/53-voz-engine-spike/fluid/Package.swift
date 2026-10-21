// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FluidReplay",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git",
                 revision: "19600a485baa4998812e4654b70d2bab8f2c9949")
    ],
    targets: [
        .executableTarget(name: "FluidReplay", dependencies: [
            .product(name: "FluidAudio", package: "FluidAudio")
        ])
    ]
)
