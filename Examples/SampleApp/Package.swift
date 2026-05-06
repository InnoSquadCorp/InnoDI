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
            exclude: [
                "Tests"
            ],
            sources: [
                "App.swift",
                "AppContainer.swift"
            ]
        ),
        .testTarget(
            name: "SampleAppTests",
            dependencies: [
                "SampleApp"
            ],
            path: "Tests"
        )
    ]
)
