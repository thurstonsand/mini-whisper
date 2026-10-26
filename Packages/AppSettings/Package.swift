// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "AppSettings", platforms: [.macOS(.v26)],
  products: [.library(name: "AppSettings", targets: ["AppSettings"])],
  dependencies: [
    .package(path: "../HotkeyListener"),
    .package(path: "../History"),
    .package(path: "../AudioCapture"),
    .package(path: "../TranscriptCleanup"),
    .package(path: "../ModelLibrary"),
  ],
  targets: [
    .target(
      name: "AppSettings",
      dependencies: [
        "HotkeyListener", "History", "AudioCapture", "TranscriptCleanup", "ModelLibrary",
      ],
    ),
    .testTarget(
      name: "AppSettingsTests",
      dependencies: [
        "AppSettings", "HotkeyListener", "AudioCapture", "TranscriptCleanup", "ModelLibrary",
      ],
    ),
  ],
)
