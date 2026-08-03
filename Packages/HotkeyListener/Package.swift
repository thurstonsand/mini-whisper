// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "HotkeyListener", platforms: [.macOS(.v14)],
  products: [.library(name: "HotkeyListener", targets: ["HotkeyListener"])],
  targets: [
    .target(name: "HotkeyListener"),
    .testTarget(name: "HotkeyListenerTests", dependencies: ["HotkeyListener"]),
  ],
)
