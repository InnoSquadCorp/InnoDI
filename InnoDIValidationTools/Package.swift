// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "InnoDIValidationTools",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .plugin(
            name: "InnoDIPrebuiltDAGValidationPlugin",
            targets: ["InnoDIPrebuiltDAGValidationPlugin"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "InnoDIPrebuiltDAGValidationCoordinator",
            path: "Artifacts/InnoDIPrebuiltDAGValidationCoordinator.artifactbundle"
        ),
        .plugin(
            name: "InnoDIPrebuiltDAGValidationPlugin",
            capability: .buildTool(),
            dependencies: [
                "InnoDIPrebuiltDAGValidationCoordinator",
            ]
        ),
    ]
)
