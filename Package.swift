// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "InnoDI",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
        .watchOS("26.0"),
        .tvOS("26.0"),
        .visionOS("26.0"),
    ],
    products: [
        .library(name: "InnoDI", targets: ["InnoDI"]),
        .executable(name: "InnoDIExamples", targets: ["InnoDIExamples"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "602.0.0")
    ],
    targets: [
        .target(
            name: "InnoDICore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ]
        ),
        .target(
            name: "InnoDI",
            dependencies: ["InnoDIMacros"]
        ),
        .executableTarget(
            name: "InnoDICLI",
            dependencies: [
                "InnoDICore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .executableTarget(
            name: "InnoDIExamples",
            dependencies: ["InnoDI"]
        ),
        .macro(
            name: "InnoDIMacros",
            dependencies: [
                "InnoDICore",
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "InnoDICoreTests",
            dependencies: [
                "InnoDICore",
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "InnoDIMacrosTests",
            dependencies: [
                "InnoDIMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "InnoDIExamplesTests",
            dependencies: ["InnoDI"]
        ),
    ]
)
