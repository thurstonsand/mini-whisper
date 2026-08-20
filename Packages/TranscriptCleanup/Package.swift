// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "TranscriptCleanup", platforms: [.macOS(.v26)],
  products: [
    .library(name: "TranscriptCleanup", targets: ["TranscriptCleanup"]),
    // A local gateway the smokes talk to over a real socket. Shared so the package smoke and the
    // app's pipeline smoke exercise the same endpoint rather than two lookalikes.
    .library(name: "CleanupTestSupport", targets: ["CleanupTestSupport"]),
    .executable(name: "cleanup-smoke", targets: ["CleanupSmoke"]),
  ],
  dependencies: [.package(path: "../FieldContext")],
  targets: [
    .target(name: "TranscriptCleanup", dependencies: ["FieldContext"]),
    .target(name: "CleanupTestSupport"),
    .executableTarget(
      name: "CleanupSmoke", dependencies: [
        "TranscriptCleanup",
        "CleanupTestSupport",
        "FieldContext",
      ],
    ),
    .testTarget(
      name: "TranscriptCleanupTests", dependencies: ["TranscriptCleanup", "FieldContext"],
    ),
  ],
)
