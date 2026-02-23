// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TCAIntegrationExample",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    dependencies: [
        .package(path: "../../"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "TCAIntegrationExample",
            dependencies: [
                "InnoDI",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]
        )
    ]
)
