// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "ASREngine", platforms: [.macOS(.v26)],
  products: [.library(name: "ASREngine", targets: ["ASREngine"])],
  dependencies: [
    .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.5"),
  ],
  targets: [
    .target(
      name: "ASREngine",
      dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
    ),
    .testTarget(name: "ASREngineTests", dependencies: ["ASREngine"]),
  ],
)
