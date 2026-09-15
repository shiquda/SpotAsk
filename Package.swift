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
        .package(path: "Vendor/textual-0.5.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .executableTarget(
            name: "SpotAsk",
            dependencies: [
                .product(name: "Textual", package: "textual-0.5.0"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SpotAskTests",
            dependencies: [
                "SpotAsk",
                .product(name: "Textual", package: "textual-0.5.0")
            ]
        )
    ]
)
