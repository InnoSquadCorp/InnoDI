// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InnoDISkillConsumer",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "InnoDISkillExample", targets: ["InnoDISkillExample"])],
    dependencies: [
        .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", exact: "7.0.0")
    ],
    targets: [
        .target(
            name: "InnoDISkillExample",
            dependencies: [
                .product(name: "InnoDI", package: "InnoDI"),
                .product(name: "InnoDISwiftUI", package: "InnoDI")
            ],
            plugins: [.plugin(name: "InnoDIDAGValidationPlugin", package: "InnoDI")]
        ),
        .testTarget(name: "InnoDISkillExampleTests", dependencies: ["InnoDISkillExample"])
    ]
)
