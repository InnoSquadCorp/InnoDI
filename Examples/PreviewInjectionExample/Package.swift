// swift-tools-version: 6.2

import PackageDescription

let innoDIPackageIdentity: String = {
    // Manifest layout is `<repoRoot>/Examples/<sample>/Package.swift`. Resolve
    // the InnoDI checkout's basename without relying on a fixed component depth
    // or force-unwrapping, then apply SwiftPM-equivalent normalization (`.git`
    // suffix stripped + lowercased). Mirrors `normalizePackageIdentity` in
    // `InnoDIBuildSupport` so the computed identity matches what SwiftPM uses
    // for `.package(path: "../../")` even when the checkout directory is
    // renamed or suffixed with `.git`.
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
    name: "PreviewInjectionExample",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "PreviewInjectionExample",
            dependencies: [
                .product(name: "InnoDISwiftUI", package: innoDIPackageIdentity)
            ],
            plugins: [
                .plugin(
                    name: "InnoDIDAGValidationPlugin",
                    package: innoDIPackageIdentity
                )
            ]
        ),
        .testTarget(
            name: "PreviewInjectionExampleTests",
            dependencies: ["PreviewInjectionExample"]
        )
    ]
)
