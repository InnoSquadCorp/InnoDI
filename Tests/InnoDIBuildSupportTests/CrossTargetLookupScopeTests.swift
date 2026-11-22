import Foundation
import Testing

@testable import InnoDIBuildSupport
@testable import InnoDIWorkspaceAnalysis

/// A plugin snapshot holds the primary target and every target it depends
/// on, so one unqualified name can declare unrelated types in several
/// targets. Each case drives the coordinator with a manifest shaped like the
/// plugin's and sits next to a control that renames one declaration.
@Suite("Cross-target lookup scope")
struct CrossTargetLookupScopeTests {
    // MARK: Custom-init preflight

    private func customInitTargets(legacyTypeName: String) -> [ScopeFixtureTarget] {
        [
            ScopeFixtureTarget(
                package: "app",
                name: "App",
                dependencies: ["app:FeatureA", "app:FeatureB"],
                files: [
                    "AppContainer.swift": """
                    import InnoDI
                    import FeatureA
                    import FeatureB

                    @DIContainer
                    struct AppContainer {
                        @Input var name: String
                    }
                    """,
                ]
            ),
            ScopeFixtureTarget(
                package: "app",
                name: "FeatureA",
                files: [
                    "Dependencies.swift": """
                    import InnoDI

                    @DIContainer
                    public struct Dependencies {
                        @Input var token: String
                    }
                    """,
                ]
            ),
            ScopeFixtureTarget(
                package: "app",
                name: "FeatureB",
                files: [
                    "Legacy.swift": """
                    public struct \(legacyTypeName) {
                        public let retries: Int
                    }

                    extension \(legacyTypeName) {
                        public init() {
                            self.init(retries: 3)
                        }
                    }
                    """,
                ]
            ),
        ]
    }

    @Test("Custom-init control: a uniquely named plain type keeps its extension init")
    func customInitControl() async throws {
        let outcome = try await runScopeFixture(
            primary: "app:App",
            targets: customInitTargets(legacyTypeName: "LegacyDependencies")
        )
        #expect(outcome.exitCode == 0)
        #expect(outcome.codes.isEmpty)
    }

    @Test("A plain type in another target that shares a container's name keeps its extension init")
    func customInitIgnoresSameNamedTypeInAnotherTarget() async throws {
        let outcome = try await runScopeFixture(
            primary: "app:App",
            targets: customInitTargets(legacyTypeName: "Dependencies")
        )
        #expect(outcome.exitCode == 0)
        #expect(!outcome.codes.contains("container.custom-init-unsupported"))
    }

    @Test("An extension init in the container's own target is still rejected")
    func customInitInContainerTargetStillFails() async throws {
        var targets = customInitTargets(legacyTypeName: "Dependencies")
        targets[1] = ScopeFixtureTarget(
            package: "app",
            name: "FeatureA",
            files: [
                "Dependencies.swift": """
                import InnoDI

                @DIContainer
                public struct Dependencies {
                    @Input var token: String
                }
                """,
                "Dependencies+Init.swift": """
                extension Dependencies {
                    init() {
                        self.init(token: "")
                    }
                }
                """,
            ]
        )
        let outcome = try await runScopeFixture(primary: "app:App", targets: targets)
        #expect(outcome.exitCode != 0)
        #expect(outcome.codes == ["container.custom-init-unsupported"])
        #expect(outcome.stderr.contains("Sources/FeatureA/Dependencies+Init.swift"))
        #expect(!outcome.stderr.contains("Sources/FeatureB/Legacy.swift"))
    }

    // MARK: Hierarchy input types

    private func hierarchyTypeTargets(vendorAliasName: String) -> [ScopeFixtureTarget] {
        [
            ScopeFixtureTarget(
                package: "app",
                name: "App",
                dependencies: ["app:Feature", "app:Core", "vendor:Vendor"],
                files: [
                    "AppContainer.swift": """
                    import InnoDI
                    import Core
                    import Feature
                    import Vendor

                    @DIContainerRole(role: ContainerRole.root)
                    struct AppContainer {
                        @Input var config: Config

                        @SubContainer(scope: .shared)
                        var feature: FeatureContainer
                    }
                    """,
                ]
            ),
            ScopeFixtureTarget(
                package: "app",
                name: "Feature",
                dependencies: ["app:Core"],
                files: [
                    "FeatureContainer.swift": """
                    import InnoDI
                    import Core

                    @DIContainerRole(role: ContainerRole.component)
                    public struct FeatureContainer {
                        @Input var config: Config
                    }
                    """,
                ]
            ),
            ScopeFixtureTarget(
                package: "app",
                name: "Core",
                files: [
                    "Config.swift": """
                    public struct Config {
                        public init() {}
                    }
                    """,
                ]
            ),
            ScopeFixtureTarget(
                package: "vendor",
                name: "Vendor",
                files: [
                    "Client.swift": """
                    public struct ClientConfiguration {
                        public init() {}
                    }

                    public struct Client {
                        public typealias \(vendorAliasName) = ClientConfiguration
                    }
                    """,
                ]
            ),
        ]
    }

    @Test("Hierarchy type control: an unrelated nested vendor alias with another name")
    func hierarchyTypeControl() async throws {
        let outcome = try await runScopeFixture(
            primary: "app:App",
            targets: hierarchyTypeTargets(vendorAliasName: "Settings")
        )
        #expect(outcome.exitCode == 0)
        #expect(outcome.codes.isEmpty)
    }

    @Test("A nested alias in another target does not answer a bare input type name")
    func hierarchyTypeIgnoresNestedAliasInAnotherTarget() async throws {
        let outcome = try await runScopeFixture(
            primary: "app:App",
            targets: hierarchyTypeTargets(vendorAliasName: "Config")
        )
        #expect(outcome.exitCode == 0)
        #expect(!outcome.codes.contains("hierarchy.unsatisfied-dependency"))
    }

    @Test("Two targets whose own aliases name different types still fail closed")
    func hierarchyTypeAliasConflictAcrossTargetsFails() async throws {
        let outcome = try await runScopeFixture(
            primary: "app:App",
            targets: [
                ScopeFixtureTarget(
                    package: "app",
                    name: "App",
                    dependencies: ["app:Feature"],
                    files: [
                        "AppContainer.swift": """
                        import InnoDI
                        import Feature

                        enum AppTypes {
                            struct Config {}
                        }

                        typealias Config = AppTypes.Config

                        @DIContainerRole(role: ContainerRole.root)
                        struct AppContainer {
                            @Input var config: Config

                            @SubContainer(scope: .shared)
                            var feature: FeatureContainer
                        }
                        """,
                    ]
                ),
                ScopeFixtureTarget(
                    package: "app",
                    name: "Feature",
                    files: [
                        "FeatureContainer.swift": """
                        import InnoDI

                        public enum FeatureTypes {
                            public struct Config {}
                        }

                        public typealias Config = FeatureTypes.Config

                        @DIContainerRole(role: ContainerRole.component)
                        public struct FeatureContainer {
                            @Input var config: Config
                        }
                        """,
                    ]
                ),
            ]
        )
        #expect(outcome.exitCode != 0)
        #expect(outcome.codes.contains("hierarchy.unsatisfied-dependency"))
    }

    // MARK: Hierarchy child references

    private func childReferenceTargets(
        vendorContainerName: String,
        vendorRole: String = "@DIContainer",
        childSpelling: String = "Cart"
    ) -> [ScopeFixtureTarget] {
        [
            ScopeFixtureTarget(
                package: "app",
                name: "App",
                dependencies: ["vendor:Vendor"],
                files: [
                    "Checkout.swift": """
                    import InnoDI
                    import Vendor

                    enum Checkout {
                        @DIContainerRole(role: ContainerRole.root)
                        struct Root {
                            @SubContainer(scope: .shared)
                            var cart: \(childSpelling)
                        }

                        @DIContainer
                        struct Cart {
                            @Provide(.shared, factory: { 1 })
                            var count: Int
                        }
                    }
                    """,
                ]
            ),
            ScopeFixtureTarget(
                package: "vendor",
                name: "Vendor",
                files: [
                    "Shop.swift": """
                    import InnoDI

                    public enum Shop {
                        \(vendorRole)
                        public struct \(vendorContainerName) {
                            @Provide(.shared, factory: { 2 })
                            var count: Int
                        }
                    }
                    """,
                ]
            ),
        ]
    }

    @Test("Child reference control: another target's nested container has another name")
    func childReferenceControl() async throws {
        let outcome = try await runScopeFixture(
            primary: "app:App",
            targets: childReferenceTargets(vendorContainerName: "Basket")
        )
        #expect(outcome.exitCode == 0)
        #expect(outcome.codes.isEmpty)
    }

    @Test("A nested container in another target does not answer a bare child name")
    func childReferenceIgnoresNestedContainerInAnotherTarget() async throws {
        let outcome = try await runScopeFixture(
            primary: "app:App",
            targets: childReferenceTargets(vendorContainerName: "Cart")
        )
        #expect(outcome.exitCode == 0)
        #expect(!outcome.codes.contains("hierarchy.ambiguous-child-reference"))
    }

    @Test(
        "A written path still reaches another target's nested component",
        arguments: ["Shop.Cart", "Vendor.Shop.Cart"]
    )
    func childReferenceReachesQualifiedNestedComponent(spelling: String) async throws {
        let outcome = try await runScopeFixture(
            primary: "app:App",
            targets: childReferenceTargets(
                vendorContainerName: "Cart",
                vendorRole: "@DIContainerRole(role: ContainerRole.component)",
                childSpelling: spelling
            )
        )
        #expect(outcome.exitCode == 0)
        #expect(outcome.codes.isEmpty)
    }

    // MARK: Orphan components

    private func orphanTargets(sdkAttribute: String) -> [ScopeFixtureTarget] {
        [
            ScopeFixtureTarget(
                package: "app",
                name: "Feature",
                dependencies: ["sdk:SDK"],
                files: [
                    "FeatureContainer.swift": """
                    import InnoDI
                    import SDK

                    public struct FeatureConfig {
                        public init() {}
                    }

                    @DIContainerRole(role: ContainerRole.component)
                    public struct FeatureContainer {
                        @Input var config: FeatureConfig
                    }
                    """,
                ]
            ),
            ScopeFixtureTarget(
                package: "sdk",
                name: "SDK",
                files: [
                    "SDKRoot.swift": """
                    import InnoDI

                    public struct SDKClient {
                        public init() {}
                    }

                    \(sdkAttribute)
                    public struct SDKRoot {
                        @Provide(.shared, factory: { SDKClient() })
                        var client: SDKClient
                    }
                    """,
                ]
            ),
        ]
    }

    @Test("Orphan control: the dependency's container has no root role")
    func orphanControl() async throws {
        let outcome = try await runScopeFixture(
            primary: "app:Feature",
            targets: orphanTargets(sdkAttribute: "@DIContainer")
        )
        #expect(outcome.exitCode == 0)
        #expect(outcome.codes.isEmpty)
    }

    @Test("A dependency's root does not orphan the primary target's component")
    func orphanIgnoresRootThatCannotMountComponent() async throws {
        let outcome = try await runScopeFixture(
            primary: "app:Feature",
            targets: orphanTargets(
                sdkAttribute: "@DIContainerRole(role: ContainerRole.root)"
            )
        )
        #expect(outcome.exitCode == 0)
        #expect(!outcome.codes.contains("hierarchy.orphan-component"))
    }

    @Test("A component that a visible root could mount but does not is still an orphan")
    func orphanReportedWhenVisibleRootCouldMount() async throws {
        let outcome = try await runScopeFixture(
            primary: "app:App",
            targets: [
                ScopeFixtureTarget(
                    package: "app",
                    name: "App",
                    dependencies: ["app:Feature"],
                    files: [
                        "AppContainer.swift": """
                        import InnoDI
                        import Feature

                        @DIContainerRole(role: ContainerRole.root)
                        struct AppContainer {
                            @Input var name: String
                        }
                        """,
                    ]
                ),
                ScopeFixtureTarget(
                    package: "app",
                    name: "Feature",
                    files: [
                        "FeatureContainer.swift": """
                        import InnoDI

                        @DIContainerRole(role: ContainerRole.component)
                        public struct FeatureContainer {
                            @Input var name: String
                        }
                        """,
                    ]
                ),
            ]
        )
        #expect(outcome.exitCode != 0)
        #expect(outcome.codes == ["hierarchy.orphan-component"])
        #expect(outcome.stderr.contains("FeatureContainer"))
    }

    @Test("A root in the component's own target still reports it as an orphan")
    func orphanReportedForSameTargetRoot() async throws {
        var targets = orphanTargets(
            sdkAttribute: "@DIContainerRole(role: ContainerRole.root)"
        )
        targets[0] = ScopeFixtureTarget(
            package: "app",
            name: "Feature",
            dependencies: ["sdk:SDK"],
            files: [
                "FeatureContainer.swift": """
                import InnoDI
                import SDK

                public struct FeatureConfig {
                    public init() {}
                }

                @DIContainerRole(role: ContainerRole.component)
                public struct FeatureContainer {
                    @Input var config: FeatureConfig
                }

                @DIContainerRole(role: ContainerRole.root)
                struct FeatureRoot {
                    @Input var config: FeatureConfig
                }
                """,
            ]
        )
        let outcome = try await runScopeFixture(primary: "app:Feature", targets: targets)
        #expect(outcome.exitCode != 0)
        #expect(outcome.codes == ["hierarchy.orphan-component"])
    }
}

private struct ScopeFixtureTarget {
    let package: String
    let name: String
    var dependencies: [String] = []
    let files: [String: String]

    var key: String { "\(package):\(name)" }
}

private struct ScopeFixtureOutcome {
    let exitCode: Int32
    let stderr: String
    let codes: [String]
}

private func scopeFixtureTargetID(_ key: String) -> WorkspaceTargetID {
    let parts = key.split(separator: ":").map(String.init)
    return .swiftPM(packageIdentity: parts[0], moduleName: parts[1])
}

/// Writes each target under its own package directory and validates the
/// primary target with a manifest that lists every target, as the build
/// plugin does.
private func runScopeFixture(
    primary: String,
    targets: [ScopeFixtureTarget]
) async throws -> ScopeFixtureOutcome {
    let root = try makeTemporaryWorkspaceRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    var manifestTargets: [WorkspaceAnalysisTarget] = []
    for target in targets {
        let packageDirectory = root.appendingPathComponent(target.package, isDirectory: true)
        var sources: [WorkspaceAnalysisSource] = []
        for (fileName, contents) in target.files.sorted(by: { $0.key < $1.key }) {
            let logicalPath = "Sources/\(target.name)/\(fileName)"
            let fileURL = packageDirectory.appendingPathComponent(logicalPath)
            try writeSource(contents, to: fileURL)
            sources.append(
                WorkspaceAnalysisSource(
                    filePath: fileURL.path,
                    logicalPath: logicalPath,
                    origin: .declared
                )
            )
        }
        let dependencies = target.dependencies.map { key -> WorkspaceAnalysisDependency in
            let parts = key.split(separator: ":").map(String.init)
            if parts[0] == target.package {
                return WorkspaceAnalysisDependency(
                    kind: .target,
                    name: parts[1],
                    targetIDs: [scopeFixtureTargetID(key)]
                )
            }
            return WorkspaceAnalysisDependency(
                kind: .product,
                name: parts[1],
                packageIdentity: parts[0],
                targetIDs: [scopeFixtureTargetID(key)]
            )
        }
        manifestTargets.append(
            WorkspaceAnalysisTarget(
                id: scopeFixtureTargetID(target.key),
                packageIdentity: target.package,
                packageDisplayName: target.package,
                packageDirectory: packageDirectory.path,
                targetName: target.name,
                moduleName: target.name,
                kind: .generic,
                role: target.key == primary ? .primary : .dependency,
                sources: sources,
                dependencies: dependencies
            )
        )
    }

    let primaryPackage = String(primary.split(separator: ":")[0])
    let manifest = WorkspaceAnalysisManifest(
        rootPackageIdentity: primaryPackage,
        rootPackageDirectory: root.appendingPathComponent(primaryPackage).path,
        primaryTargetID: scopeFixtureTargetID(primary),
        targets: manifestTargets
    )
    let outcome = try await ValidationCoordinator.coordinate(
        manifest: manifest,
        stateDirectoryPath: root.appendingPathComponent("state").path,
        outputDirectoryPath: root.appendingPathComponent("out").path,
        runner: InProcessValidationCommandRunner(),
        verboseLoggingEnabled: false
    )
    return ScopeFixtureOutcome(
        exitCode: outcome.result.exitCode,
        stderr: outcome.result.stderr,
        codes: outcome.metricsArtifact.issues.map(\.code)
    )
}
