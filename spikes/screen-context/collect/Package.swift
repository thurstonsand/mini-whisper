// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "ScreenCollect", platforms: [.macOS(.v26)],
  dependencies: [.package(path: "../../../Packages/FieldContext")],
  targets: [
    .executableTarget(
      name: "screen-collect", dependencies: [.product(
        name: "FieldContext",
        package: "FieldContext",
      )],
    ),
    .executableTarget(
      name: "recompose", dependencies: [.product(name: "FieldContext", package: "FieldContext")],
    ),
    .executableTarget(name: "hotkey"),
  ],
)
