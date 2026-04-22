// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PreviewInjectionExample",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "PreviewInjectionExample",
            dependencies: [
                .product(name: "InnoDISwiftUI", package: "InnoDI")
            ]
        ),
        .testTarget(
            name: "PreviewInjectionExampleTests",
            dependencies: ["PreviewInjectionExample"]
        )
    ]
)
