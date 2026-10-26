// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "LocalCleanup", platforms: [.macOS(.v26)],
  products: [.library(name: "LocalCleanup", targets: ["LocalCleanup"])],
  dependencies: [.package(path: "../ModelLibrary")],
  targets: [
    // llama.cpp's own release artifact, pinned by build number and checksum: the runtime is
    // whatever these bytes are, and nothing resolves to a newer one behind our back.
    .binaryTarget(
      name: "llama",
      url: "https://github.com/ggml-org/llama.cpp/releases/download/b11801/llama-b11801-xcframework.zip",
      checksum: "188a0c411c52f729d4bf188b0e2ca5759ab89da386c77ac36f492d1a4742721b",
    ),
    .target(name: "LocalCleanup", dependencies: ["llama", "ModelLibrary"]),
    .testTarget(name: "LocalCleanupTests", dependencies: ["LocalCleanup", "ModelLibrary"]),
  ],
)
