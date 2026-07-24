// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WhisperKitHarness",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            name: "argmax-oss-swift",
            path: "../../.artifacts/argmax-oss-swift"
        )
    ],
    targets: [
        .executableTarget(
            name: "WhisperKitHarness",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ]
        )
    ]
)
