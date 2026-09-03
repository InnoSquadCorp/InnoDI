// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

// SwiftPM in the Xcode 27.0 preview reports DocC catalogs as unhandled target
// inputs when compiler warnings are promoted to errors. Keep ordinary strict
// builds warning-free on that toolchain. Tools/generate-docc.sh re-enables the
// catalogs in its isolated documentation package before invoking DocC.
func documentationCatalogBuildExcludes(_ catalog: String) -> [String] {
    #if swift(>=6.4)
    [catalog]
    #else
    []
    #endif
}

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
        .executable(name: "InnoDI-DependencyGraph", targets: ["InnoDI-DependencyGraph"]),
        .executable(name: "InnoDI-Migrate", targets: ["InnoDI-Migrate"]),
        .plugin(name: "InnoDIDAGValidationPlugin", targets: ["InnoDIDAGValidationPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.2"),
    ],
    targets: [
        .target(
            name: "InnoDICore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ],
            exclude: documentationCatalogBuildExcludes("InnoDICore.docc")
        ),
        .target(
            name: "InnoDIWorkspaceAnalysis",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
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
            dependencies: ["InnoDIMacros"],
            exclude: documentationCatalogBuildExcludes("InnoDI.docc"),
            resources: [
                .copy("PrivacyInfo.xcprivacy"),
            ]
        ),
        .target(
            name: "InnoDISwiftUI",
            dependencies: ["InnoDI"],
            resources: [
                .copy("PrivacyInfo.xcprivacy"),
            ]
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
            path: "Sources/InnoDIBuildSupport"
        ),
        .target(
            name: "InnoDIDependencyGraphCore",
            dependencies: [
                "InnoDICore",
                "InnoDIWorkspaceAnalysis",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
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
            ]
        ),
        .target(
            name: "InnoDIMigrationCore",
            dependencies: [
                "InnoDICore",
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),
        .executableTarget(
            name: "InnoDI-DependencyGraph",
            dependencies: [
                "InnoDIDependencyGraphCLI"
            ]
        ),
        .executableTarget(
            name: "InnoDI-Migrate",
            dependencies: [
                "InnoDIMigrationCore"
            ]
        ),
        .executableTarget(
            name: "InnoDI-DAGValidationCoordinator",
            dependencies: [
                "InnoDIBuildSupport"
            ]
        ),
        .executableTarget(
            name: "InnoDI-DeferredAliasScan",
            dependencies: [
                "InnoDIWorkspaceAnalysis"
            ]
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
                "InnoDI-DependencyGraph",
                "InnoDIDependencyGraphCLI",
                "InnoDIDependencyGraphCore",
                "InnoDIBuildSupport",
                "InnoDIWorkspaceAnalysis",
                "InnoDITestSupport",
            ],
            exclude: ["__Snapshots__"]
        ),
        .testTarget(
            name: "InnoDIMigrationCoreTests",
            dependencies: [
                "InnoDI-Migrate",
                "InnoDIMigrationCore",
                "InnoDITestSupport",
            ]
        ),
        .testTarget(
            name: "InnoDIBuildSupportTests",
            dependencies: [
                "InnoDIBuildSupport",
                "InnoDICore",
                "InnoDIWorkspaceAnalysis",
                "InnoDITestSupport"
            ]
        ),
        .testTarget(
            name: "InnoDIRuntimeTests",
            dependencies: [
                "InnoDI"
            ]
        ),
        .testTarget(
            name: "InnoDISwiftUITests",
            dependencies: [
                "InnoDISwiftUI"
            ]
        ),
    ]
)
