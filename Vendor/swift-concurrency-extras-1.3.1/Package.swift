// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "swift-concurrency-extras",
  platforms: [
    .iOS(.v13),
    .macOS(.v10_15),
    .tvOS(.v13),
    .watchOS(.v6),
  ],
  products: [
    .library(
      name: "ConcurrencyExtras",
      targets: ["ConcurrencyExtras"]
    )
  ],
  targets: [
    .target(
      name: "ConcurrencyExtras"
    ),
    .testTarget(
      name: "ConcurrencyExtrasTests",
      dependencies: [
        "ConcurrencyExtras"
      ]
    ),
  ]
)

for target in package.targets {
  target.swiftSettings = target.swiftSettings ?? []
  target.swiftSettings!.append(contentsOf: [
    .enableExperimentalFeature("StrictConcurrency")
  ])
}
