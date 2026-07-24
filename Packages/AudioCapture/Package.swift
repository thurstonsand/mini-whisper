// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "AudioCapture", platforms: [.macOS(.v14)],
  products: [.library(name: "AudioCapture", targets: ["AudioCapture"])],
  targets: [
    .target(name: "AudioCapture"),
    .testTarget(name: "AudioCaptureTests", dependencies: ["AudioCapture"]),
  ])
