// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpotAsk",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "SpotAsk", targets: ["SpotAsk"])
    ],
    dependencies: [
        .package(path: "Vendor/textual-0.5.0")
    ],
    targets: [
        .executableTarget(
            name: "SpotAsk",
            dependencies: [
                .product(name: "Textual", package: "textual-0.5.0")
            ]
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
