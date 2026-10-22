// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpotAsk",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "SpotAsk", targets: ["SpotAsk"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .executableTarget(
            name: "SpotAsk",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .process("Resources"),
                .copy("SessionDocument"),
            ]
        ),
        .testTarget(
            name: "SpotAskTests",
            dependencies: [
                "SpotAsk",
            ]
        )
    ]
)
