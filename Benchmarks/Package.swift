// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "InnoDIBenchmarks",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "BenchmarkHarness", targets: ["BenchmarkHarness"])
    ],
    dependencies: [
        .package(path: "../")
    ],
    targets: [
        .executableTarget(
            name: "BenchmarkHarness",
            dependencies: [
                .product(name: "InnoDI", package: "InnoDI")
            ]
        )
    ]
)
