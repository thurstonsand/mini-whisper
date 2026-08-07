// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "AppSettings", platforms: [.macOS(.v26)],
  products: [.library(name: "AppSettings", targets: ["AppSettings"])],
  dependencies: [
    .package(path: "../HotkeyListener"),
    .package(path: "../History"),
    .package(path: "../AudioCapture"),
  ],
  targets: [
    .target(name: "AppSettings", dependencies: ["HotkeyListener", "History", "AudioCapture"]),
    .testTarget(
      name: "AppSettingsTests", dependencies: ["AppSettings", "HotkeyListener", "AudioCapture"],
    ),
  ],
)
