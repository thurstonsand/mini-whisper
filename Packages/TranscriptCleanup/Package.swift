// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "TranscriptCleanup", platforms: [.macOS(.v26)],
  products: [
    .library(name: "TranscriptCleanup", targets: ["TranscriptCleanup"]),
    .executable(name: "cleanup-smoke", targets: ["CleanupSmoke"]),
  ],
  dependencies: [.package(path: "../FieldContext")],
  targets: [
    .target(name: "TranscriptCleanup", dependencies: ["FieldContext"]),
    .executableTarget(name: "CleanupSmoke", dependencies: ["TranscriptCleanup", "FieldContext"]),
    .testTarget(
      name: "TranscriptCleanupTests", dependencies: ["TranscriptCleanup", "FieldContext"],
    ),
  ],
)
