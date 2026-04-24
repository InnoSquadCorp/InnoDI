// swift-tools-version: 6.2

import PackageDescription

let innoDIPackageIdentity = #filePath
    .split(separator: "/")
    .dropLast(3)
    .last
    .map(String.init)!
    .lowercased()

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
                .product(name: "InnoDISwiftUI", package: innoDIPackageIdentity)
            ]
        ),
        .testTarget(
            name: "SwiftUIExampleTests",
            dependencies: ["SwiftUIExample"]
        )
    ]
)
