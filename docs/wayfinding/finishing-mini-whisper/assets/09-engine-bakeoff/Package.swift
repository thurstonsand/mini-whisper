// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "EngineBakeoff",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            name: "transcribe-cpp",
            path: ".artifacts/transcribe.cpp/bindings/swift"
        )
    ],
    targets: [
        .executableTarget(
            name: "EngineBakeoff",
            dependencies: [
                .product(name: "TranscribeCpp", package: "transcribe-cpp")
            ]
        )
    ]
)
