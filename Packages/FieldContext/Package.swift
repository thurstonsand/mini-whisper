// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "FieldContext", platforms: [.macOS(.v26)],
  products: [.library(name: "FieldContext", targets: ["FieldContext"])],
  targets: [
    .target(name: "FieldContext"),
    .testTarget(name: "FieldContextTests", dependencies: ["FieldContext"]),
  ],
)
