// swift-tools-version: 6.2

import PackageDescription

let innoDIPackageIdentity: String = {
    // SwiftPM derives local dependency identity from the checkout directory,
    // not Package.name. Match the normalization used by the other examples.
    let components = #filePath.split(separator: "/", omittingEmptySubsequences: true)
    let basename: String
    if let examplesOffset = components.lastIndex(of: "Examples"),
       examplesOffset > components.startIndex {
        basename = String(components[components.index(before: examplesOffset)])
    } else {
        basename = "innodi"
    }
    var identity = basename.lowercased()
    if identity.hasSuffix(".git") {
        identity.removeLast(".git".count)
    }
    return identity.isEmpty ? "innodi" : identity
}()

let package = Package(
    name: "SampleApp",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "SampleApp",
            dependencies: [
                .product(name: "InnoDI", package: innoDIPackageIdentity)
            ],
            path: ".",
            exclude: [
                "Tests"
            ],
            sources: [
                "App.swift",
                "AppContainer.swift"
            ],
            plugins: [
                .plugin(
                    name: "InnoDIDAGValidationPlugin",
                    package: innoDIPackageIdentity
                )
            ]
        ),
        .testTarget(
            name: "SampleAppTests",
            dependencies: [
                "SampleApp"
            ],
            path: "Tests"
        )
    ]
)
