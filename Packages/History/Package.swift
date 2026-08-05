// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "History", platforms: [.macOS(.v14)],
  products: [.library(name: "History", targets: ["History"])],
  dependencies: [.package(path: "../AudioCapture")],
  targets: [
    .target(name: "History", dependencies: ["AudioCapture"]),
    .testTarget(name: "HistoryTests", dependencies: ["History", "AudioCapture"]),
  ],
)
