// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SampleApp",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "SampleApp",
            dependencies: [
                .product(name: "InnoDI", package: "InnoDI")
            ],
            path: ".",
            sources: [
                "App.swift",
                "AppContainer.swift"
            ]
        )
    ]
)
