// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VozReplay",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core", revision: "a7a70e4e42958d6b9c1eb67402d84cb47a14c507")
    ],
    targets: [
        .executableTarget(name: "VozReplay", dependencies: [.product(name: "Voz", package: "desert-ant-core")])
    ]
)
