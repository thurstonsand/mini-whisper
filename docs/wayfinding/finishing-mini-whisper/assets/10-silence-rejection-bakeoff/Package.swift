// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "SilenceBakeoffTranscriber", platforms: [.macOS(.v14)],
  dependencies: [
    .package(name: "ASREngine", path: "../../../../../Packages/ASREngine"),
    .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.5"),
  ],
  targets: [
    .executableTarget(
      name: "SilenceBakeoffTranscriber",
      dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
    .executableTarget(
      name: "SilenceBakeoffVad",
      dependencies: [
        .product(name: "ASREngine", package: "ASREngine"),
        .product(name: "FluidAudio", package: "FluidAudio"),
      ]),
  ])
