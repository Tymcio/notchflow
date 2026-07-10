// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchFlow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NotchFlow", targets: ["NotchFlow"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "NotchFlow",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle", condition: .when(platforms: [.macOS]))
            ],
            path: "Sources/NotchFlow",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "NotchFlowTests",
            dependencies: ["NotchFlow"],
            path: "Tests/NotchFlowTests"
        )
    ]
)
