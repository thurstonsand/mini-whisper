// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "SpeechDictionary", platforms: [.macOS(.v26)],
  products: [.library(name: "SpeechDictionary", targets: ["SpeechDictionary"])],
  targets: [
    .target(name: "SpeechDictionary"),
    .testTarget(name: "SpeechDictionaryTests", dependencies: ["SpeechDictionary"]),
  ],
)
