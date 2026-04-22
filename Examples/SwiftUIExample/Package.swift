// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftUIExample",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "SwiftUIExample",
            dependencies: [
                .product(name: "InnoDISwiftUI", package: "InnoDI")
            ]
        ),
        .testTarget(
            name: "SwiftUIExampleTests",
            dependencies: ["SwiftUIExample"]
        )
    ]
)
