// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "InnoDI",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
        .watchOS(.v10),
        .tvOS(.v17),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "InnoDI", targets: ["InnoDI"]),
        .plugin(name: "InnoDIDAGValidationPlugin", targets: ["InnoDIDAGValidationPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
    ],
    targets: [
        .target(
            name: "InnoDICore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ]
        ),
        .target(
            name: "InnoDITestSupport",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
            ],
            path: "Tests/TestSupport"
        ),
        .target(
            name: "InnoDI",
            dependencies: ["InnoDIMacros"]
        ),
        .target(
            name: "InnoDIBuildSupport"
            ,
            dependencies: [
                "InnoDICore",
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),
        .executableTarget(
            name: "InnoDI-DependencyGraph",
            dependencies: [
                "InnoDICore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .executableTarget(
            name: "InnoDI-DAGValidationCoordinator",
            dependencies: [
                "InnoDIBuildSupport"
            ]
        ),
        .plugin(
            name: "InnoDIDAGValidationPlugin",
            capability: .buildTool(),
            dependencies: [
                "InnoDI-DAGValidationCoordinator",
                "InnoDI-DependencyGraph"
            ]
        ),
        .macro(
            name: "InnoDIMacros",
            dependencies: [
                "InnoDICore",
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "InnoDICoreTests",
            dependencies: [
                "InnoDICore",
                "InnoDITestSupport",
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "InnoDIMacrosTests",
            dependencies: [
                "InnoDIMacros",
                "InnoDITestSupport",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
            ],
            exclude: ["__Snapshots__"]
        ),
        .testTarget(
            name: "InnoDIDependencyGraphCLITests",
            dependencies: [
                "InnoDI-DependencyGraph"
            ]
        ),
        .testTarget(
            name: "InnoDIBuildSupportTests",
            dependencies: [
                "InnoDIBuildSupport",
                "InnoDICore"
            ]
        ),
    ]
)
