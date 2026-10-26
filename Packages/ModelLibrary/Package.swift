// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "ModelLibrary", platforms: [.macOS(.v26)],
  products: [.library(name: "ModelLibrary", targets: ["ModelLibrary"])],
  targets: [
    .target(name: "ModelLibrary"),
    .testTarget(name: "ModelLibraryTests", dependencies: ["ModelLibrary"]),
  ],
)
