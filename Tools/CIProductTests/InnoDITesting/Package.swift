// swift-tools-version: 6.2

import PackageDescription

// Match SwiftPM's local-package identity even in a renamed checkout.
let components = #filePath.split(separator: "/", omittingEmptySubsequences: true)
var rootIdentity = String(components[components.count - 5]).lowercased()
if rootIdentity.hasSuffix(".git") { rootIdentity.removeLast(4) }

let package = Package(
    name: "InnoDITestingProductTests",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
        .tvOS(.v17),
        .visionOS(.v1)
    ],
    dependencies: [.package(path: "../../..")],
    targets: [
        .testTarget(
            name: "InnoDITestingTests",
            dependencies: [.product(name: "InnoDITesting", package: rootIdentity)]
        )
    ]
)
