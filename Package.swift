// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

// Package-wide swiftSettings. We opt the package into the Swift 6
// upcoming-feature set so consumer builds see the same concurrency /
// sendable rules the CI matrix enforces. Using `.enableUpcomingFeature`
// (rather than `.swiftLanguageMode(.v6)`) keeps the package importable
// from Swift 5 consumers while still surfacing warnings in this codebase.
//
// `InferSendableFromCaptures` and `GlobalActorIsolatedTypesUsability` are
// intentionally not listed — Swift 6.2's implicit language mode already
// enables them, and the compiler emits a noise warning when you re-assert
// a feature that's already active.
let innoDISharedSwiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
]

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
        .library(name: "InnoDISwiftUI", targets: ["InnoDISwiftUI"]),
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
            ],
            swiftSettings: innoDISharedSwiftSettings
        ),
        .target(
            name: "InnoDIWorkspaceAnalysis",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ],
            swiftSettings: innoDISharedSwiftSettings
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
            path: "Tests/TestSupport",
            swiftSettings: innoDISharedSwiftSettings
        ),
        .target(
            name: "InnoDI",
            dependencies: ["InnoDIMacros"],
            resources: [
                .copy("PrivacyInfo.xcprivacy"),
            ],
            swiftSettings: innoDISharedSwiftSettings
        ),
        .target(
            name: "InnoDISwiftUI",
            dependencies: ["InnoDI", "InnoDIMacros"],
            resources: [
                .copy("PrivacyInfo.xcprivacy"),
            ],
            swiftSettings: innoDISharedSwiftSettings
        ),
        .target(
            name: "InnoDIBuildSupport",
            dependencies: [
                "InnoDICore",
                "InnoDIDependencyGraphCore",
                "InnoDIWorkspaceAnalysis",
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ],
            swiftSettings: innoDISharedSwiftSettings
        ),
        .target(
            name: "InnoDIDependencyGraphCore",
            dependencies: [
                "InnoDICore",
                "InnoDIWorkspaceAnalysis",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ],
            swiftSettings: innoDISharedSwiftSettings
        ),
        .target(
            name: "InnoDIDependencyGraphCLI",
            dependencies: [
                "InnoDICore",
                "InnoDIDependencyGraphCore",
                "InnoDIWorkspaceAnalysis",
                // Added for the `--diagnose-lock` subcommand: it uses
                // FilesystemTypeDetector and the lock-metadata
                // codecs to surface the same view of the world the
                // build plugin sees. The plugin already builds both
                // targets, so this introduces no new transitive cost.
                "InnoDIBuildSupport",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            swiftSettings: innoDISharedSwiftSettings
        ),
        .executableTarget(
            name: "InnoDI-DependencyGraph",
            dependencies: [
                "InnoDIDependencyGraphCLI"
            ],
            swiftSettings: innoDISharedSwiftSettings
        ),
        .executableTarget(
            name: "InnoDI-DAGValidationCoordinator",
            dependencies: [
                "InnoDIBuildSupport"
            ],
            swiftSettings: innoDISharedSwiftSettings
        ),
        .executableTarget(
            name: "InnoDI-DeferredAliasScan",
            dependencies: [
                "InnoDIWorkspaceAnalysis"
            ],
            swiftSettings: innoDISharedSwiftSettings
        ),
        .plugin(
            name: "InnoDIDAGValidationPlugin",
            capability: .buildTool(),
            dependencies: [
                "InnoDI-DAGValidationCoordinator"
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
            ],
            swiftSettings: innoDISharedSwiftSettings
        ),
        .testTarget(
            name: "InnoDICoreTests",
            dependencies: [
                "InnoDICore",
                "InnoDITestSupport",
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            swiftSettings: innoDISharedSwiftSettings
        ),
        .testTarget(
            name: "InnoDIMacrosTests",
            dependencies: [
                "InnoDIMacros",
                "InnoDITestSupport",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
            ],
            exclude: ["__Snapshots__"],
            swiftSettings: innoDISharedSwiftSettings
        ),
        .testTarget(
            name: "InnoDIDependencyGraphCLITests",
            dependencies: [
                "InnoDI-DependencyGraph",
                "InnoDIDependencyGraphCLI",
                "InnoDIDependencyGraphCore",
                "InnoDIBuildSupport",
                "InnoDITestSupport",
            ],
            exclude: ["__Snapshots__"],
            swiftSettings: innoDISharedSwiftSettings
        ),
        .testTarget(
            name: "InnoDIBuildSupportTests",
            dependencies: [
                "InnoDIBuildSupport",
                "InnoDICore",
                "InnoDIWorkspaceAnalysis",
                "InnoDITestSupport"
            ],
            swiftSettings: innoDISharedSwiftSettings
        ),
        .testTarget(
            name: "InnoDIRuntimeTests",
            dependencies: [
                "InnoDI"
            ],
            swiftSettings: innoDISharedSwiftSettings
        ),
        .testTarget(
            name: "InnoDISwiftUITests",
            dependencies: [
                "InnoDISwiftUI"
            ],
            swiftSettings: innoDISharedSwiftSettings
        ),
    ]
)
