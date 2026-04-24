// swift-tools-version: 6.2

import PackageDescription

let innoDIPackageIdentity = #filePath
    .split(separator: "/")
    .dropLast(3)
    .last
    .map(String.init)!
    .lowercased()

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
                .product(name: "InnoDISwiftUI", package: innoDIPackageIdentity)
            ]
        ),
        .testTarget(
            name: "PreviewInjectionExampleTests",
            dependencies: ["PreviewInjectionExample"]
        )
    ]
)
