// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "History", platforms: [.macOS(.v26)],
  products: [.library(name: "History", targets: ["History"])],
  dependencies: [.package(path: "../AudioCapture"), .package(path: "../FieldContext")],
  targets: [
    .target(name: "History", dependencies: ["AudioCapture", "FieldContext"]),
    .testTarget(name: "HistoryTests", dependencies: ["History", "AudioCapture", "FieldContext"]),
  ],
)
