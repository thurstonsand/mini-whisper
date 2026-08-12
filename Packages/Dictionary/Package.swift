// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "Dictionary", platforms: [.macOS(.v26)],
  products: [.library(name: "Dictionary", targets: ["Dictionary"])],
  targets: [
    .target(name: "Dictionary"),
    .testTarget(name: "DictionaryTests", dependencies: ["Dictionary"]),
  ],
)
