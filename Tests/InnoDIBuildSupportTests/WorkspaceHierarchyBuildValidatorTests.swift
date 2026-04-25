import Foundation
import Testing
import InnoDITestSupport

@testable import InnoDIBuildSupport

@Suite("WorkspaceHierarchyBuildValidator", .tags(.hierarchyValidation))
struct WorkspaceHierarchyBuildValidatorTests {
    @Test("SwiftPM multi-target rooted hierarchy passes when parent satisfies component inputs")
    func swiftPMValidHierarchyPasses() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(name: "FeatureModule"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.isEmpty)
    }

    @Test("SwiftPM hierarchy fails when cross-module child is not marked DIComponent")
    func swiftPMChildNotComponentFails() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(name: "FeatureModule"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.contains { $0.code == "hierarchy.child-not-component" })
    }

    @Test("SwiftPM hierarchy fails when parent cannot satisfy child component input contract")
    func swiftPMUnsatisfiedDependencyFails() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(name: "FeatureModule"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var session: Session
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.contains { $0.code == "hierarchy.unsatisfied-dependency" })
    }

    @Test("SwiftPM hierarchy reports orphan components outside all DIHierarchyRoot trees")
    func swiftPMOrphanComponentFails() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(name: "FeatureModule"),
                    .target(name: "OrphanModule"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Sources/FeatureModule/FeatureContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct OrphanContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Sources/OrphanModule/OrphanContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.contains { $0.code == "hierarchy.orphan-component" })
    }

    @Test("SwiftPM hierarchy reports duplicate parent mounts for the same component")
    func swiftPMDuplicateParentFails() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(name: "FeatureModule"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var shell: ShellContainer
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }

            @DIContainer
            struct ShellContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.contains { $0.code == "hierarchy.duplicate-parent" })
    }

    @Test("SwiftPM hierarchy reports cycles reachable from a hierarchy root")
    func swiftPMCycleFails() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(name: "FeatureModule"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }

            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var app: AppContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.contains { $0.code == "hierarchy.component-cycle" })
    }

    @Test("Tuist multi-module hierarchy passes with matching project graph edges")
    func tuistValidHierarchyPasses() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try """
        import ProjectDescription

        let project = Project(
            name: "Workspace",
            targets: [
                .target(
                    name: "AppFeature",
                    destinations: .iOS,
                    product: .framework,
                    bundleId: "app.feature",
                    sources: ["Projects/AppFeature/Sources/**"],
                    dependencies: [.target(name: "FeatureModule")]
                ),
                .target(
                    name: "FeatureModule",
                    destinations: .iOS,
                    product: .framework,
                    bundleId: "feature.module",
                    sources: ["Projects/FeatureModule/Sources/**"]
                ),
            ]
        )
        """.write(
            to: rootURL.appendingPathComponent("Project.swift"),
            atomically: true,
            encoding: .utf8
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Projects/AppFeature/Sources/AppContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Projects/FeatureModule/Sources/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.isEmpty)
    }

    @Test("Tuist hierarchy fails when project graph omits the child module edge")
    func tuistMissingModuleEdgeFails() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try """
        import ProjectDescription

        let project = Project(
            name: "Workspace",
            targets: [
                .target(
                    name: "AppFeature",
                    destinations: .iOS,
                    product: .framework,
                    bundleId: "app.feature",
                    sources: ["Projects/AppFeature/Sources/**"]
                ),
                .target(
                    name: "FeatureModule",
                    destinations: .iOS,
                    product: .framework,
                    bundleId: "feature.module",
                    sources: ["Projects/FeatureModule/Sources/**"]
                ),
            ]
        )
        """.write(
            to: rootURL.appendingPathComponent("Project.swift"),
            atomically: true,
            encoding: .utf8
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Projects/AppFeature/Sources/AppContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Projects/FeatureModule/Sources/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.contains { $0.code == "hierarchy.module-edge-missing" })
    }

    @Test("SwiftPM multi-package hierarchy keeps same-named target modules distinct")
    func swiftPMMultiPackageSameNamedTargetsStayDistinct() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                dependencies: [
                    .package(name: "AlphaPkg", path: "Packages/AlphaPkg"),
                    .package(name: "BetaPkg", path: "Packages/BetaPkg"),
                ],
                targets: [
                    .target(
                        name: "AppFeature",
                        dependencies: [.product(name: "Shared", package: "AlphaPkg")]
                    ),
                ]
            )
            """,
            to: rootURL.appendingPathComponent("Package.swift")
        )
        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "AlphaPkg",
                products: [.library(name: "Shared", targets: ["Shared"])],
                targets: [.target(name: "Shared")]
            )
            """,
            to: rootURL.appendingPathComponent("Packages/AlphaPkg/Package.swift")
        )
        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "BetaPkg",
                products: [.library(name: "Shared", targets: ["Shared"])],
                targets: [.target(name: "Shared")]
            )
            """,
            to: rootURL.appendingPathComponent("Packages/BetaPkg/Package.swift")
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var alpha: AlphaFeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct AlphaFeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Packages/AlphaPkg/Sources/Shared/AlphaFeatureContainer.swift")
        )
        try writeSource(
            """
            @DIContainer
            struct BetaFeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Packages/BetaPkg/Sources/Shared/BetaFeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.isEmpty)
    }

    @Test("SwiftPM multi-package hierarchy reports missing edge against the correct same-named target")
    func swiftPMMultiPackageSameNamedTargetsMissingEdgeFails() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                dependencies: [
                    .package(name: "AlphaPkg", path: "Packages/AlphaPkg"),
                    .package(name: "BetaPkg", path: "Packages/BetaPkg"),
                ],
                targets: [
                    .target(
                        name: "AppFeature",
                        dependencies: [.product(name: "Shared", package: "BetaPkg")]
                    ),
                ]
            )
            """,
            to: rootURL.appendingPathComponent("Package.swift")
        )
        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "AlphaPkg",
                products: [.library(name: "Shared", targets: ["Shared"])],
                targets: [.target(name: "Shared")]
            )
            """,
            to: rootURL.appendingPathComponent("Packages/AlphaPkg/Package.swift")
        )
        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "BetaPkg",
                products: [.library(name: "Shared", targets: ["Shared"])],
                targets: [.target(name: "Shared")]
            )
            """,
            to: rootURL.appendingPathComponent("Packages/BetaPkg/Package.swift")
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var alpha: AlphaFeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct AlphaFeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Packages/AlphaPkg/Sources/Shared/AlphaFeatureContainer.swift")
        )
        try writeSource(
            """
            @DIContainer
            struct BetaFeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Packages/BetaPkg/Sources/Shared/BetaFeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.contains { $0.code == "hierarchy.module-edge-missing" })
    }

    @Test("Tuist multi-project hierarchy keeps same-named target modules distinct")
    func tuistMultiProjectSameNamedTargetsStayDistinct() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSource(
        """
        import ProjectDescription

        let project = Project(
            name: "AppProject",
            targets: [
                .target(
                    name: "AppFeature",
                    destinations: .iOS,
                    product: .framework,
                    bundleId: "app.feature",
                    sources: ["Sources/**"],
                    dependencies: [.project(target: "Shared", path: "../SharedAlpha")]
                ),
            ]
        )
        """,
            to: rootURL.appendingPathComponent("Projects/AppProject/Project.swift")
        )
        try writeSource(
        """
        import ProjectDescription

        let project = Project(
            name: "SharedAlpha",
            targets: [
                .target(
                    name: "Shared",
                    destinations: .iOS,
                    product: .framework,
                    bundleId: "shared.alpha",
                    sources: ["Sources/**"]
                ),
            ]
        )
        """,
            to: rootURL.appendingPathComponent("Projects/SharedAlpha/Project.swift")
        )
        try writeSource(
        """
        import ProjectDescription

        let project = Project(
            name: "SharedBeta",
            targets: [
                .target(
                    name: "Shared",
                    destinations: .iOS,
                    product: .framework,
                    bundleId: "shared.beta",
                    sources: ["Sources/**"]
                ),
            ]
        )
        """,
            to: rootURL.appendingPathComponent("Projects/SharedBeta/Project.swift")
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var alpha: AlphaFeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Projects/AppProject/Sources/AppContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct AlphaFeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Projects/SharedAlpha/Sources/AlphaFeatureContainer.swift")
        )
        try writeSource(
            """
            @DIContainer
            struct BetaFeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Projects/SharedBeta/Sources/BetaFeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.isEmpty)
    }

    @Test("Tuist multi-project hierarchy reports missing edge against the correct same-named target")
    func tuistMultiProjectSameNamedTargetsMissingEdgeFails() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSource(
        """
        import ProjectDescription

        let project = Project(
            name: "AppProject",
            targets: [
                .target(
                    name: "AppFeature",
                    destinations: .iOS,
                    product: .framework,
                    bundleId: "app.feature",
                    sources: ["Sources/**"],
                    dependencies: [.project(target: "Shared", path: "../SharedBeta")]
                ),
            ]
        )
        """,
            to: rootURL.appendingPathComponent("Projects/AppProject/Project.swift")
        )
        try writeSource(
        """
        import ProjectDescription

        let project = Project(
            name: "SharedAlpha",
            targets: [
                .target(
                    name: "Shared",
                    destinations: .iOS,
                    product: .framework,
                    bundleId: "shared.alpha",
                    sources: ["Sources/**"]
                ),
            ]
        )
        """,
            to: rootURL.appendingPathComponent("Projects/SharedAlpha/Project.swift")
        )
        try writeSource(
        """
        import ProjectDescription

        let project = Project(
            name: "SharedBeta",
            targets: [
                .target(
                    name: "Shared",
                    destinations: .iOS,
                    product: .framework,
                    bundleId: "shared.beta",
                    sources: ["Sources/**"]
                ),
            ]
        )
        """,
            to: rootURL.appendingPathComponent("Projects/SharedBeta/Project.swift")
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var alpha: AlphaFeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Projects/AppProject/Sources/AppContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct AlphaFeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Projects/SharedAlpha/Sources/AlphaFeatureContainer.swift")
        )
        try writeSource(
            """
            @DIContainer
            struct BetaFeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Projects/SharedBeta/Sources/BetaFeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.contains { $0.code == "hierarchy.module-edge-missing" })
    }

    @Test("Same-module child wins when multiple containers share the same nominal path")
    func sameModuleChildTakesPriorityOverCrossModuleCandidates() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                dependencies: [
                    .package(name: "AlphaPkg", path: "Packages/AlphaPkg"),
                ],
                targets: [
                    .target(
                        name: "AppFeature",
                        dependencies: [.product(name: "FeatureKit", package: "AlphaPkg")]
                    ),
                ]
            )
            """,
            to: rootURL.appendingPathComponent("Package.swift")
        )
        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "AlphaPkg",
                products: [.library(name: "FeatureKit", targets: ["FeatureModule"])],
                targets: [.target(name: "FeatureModule")]
            )
            """,
            to: rootURL.appendingPathComponent("Packages/AlphaPkg/Package.swift")
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }

            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Packages/AlphaPkg/Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(!report.issues.contains { $0.code == "hierarchy.ambiguous-child-reference" })
        #expect(report.issues.isEmpty)
    }

    @Test("Same-named child containers across dependency modules fail with an explicit ambiguity diagnostic")
    func ambiguousSameNamedCrossModuleContainersFailExplicitly() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                dependencies: [
                    .package(name: "AlphaPkg", path: "Packages/AlphaPkg"),
                    .package(name: "BetaPkg", path: "Packages/BetaPkg"),
                ],
                targets: [
                    .target(
                        name: "AppFeature",
                        dependencies: [
                            .product(name: "AlphaFeatureKit", package: "AlphaPkg"),
                            .product(name: "BetaFeatureKit", package: "BetaPkg"),
                        ]
                    ),
                ]
            )
            """,
            to: rootURL.appendingPathComponent("Package.swift")
        )
        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "AlphaPkg",
                products: [.library(name: "AlphaFeatureKit", targets: ["AlphaFeatureModule"])],
                targets: [.target(name: "AlphaFeatureModule")]
            )
            """,
            to: rootURL.appendingPathComponent("Packages/AlphaPkg/Package.swift")
        )
        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "BetaPkg",
                products: [.library(name: "BetaFeatureKit", targets: ["BetaFeatureModule"])],
                targets: [.target(name: "BetaFeatureModule")]
            )
            """,
            to: rootURL.appendingPathComponent("Packages/BetaPkg/Package.swift")
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Packages/AlphaPkg/Sources/AlphaFeatureModule/FeatureContainer.swift")
        )
        try writeSource(
            """
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Packages/BetaPkg/Sources/BetaFeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.contains { $0.code == "hierarchy.ambiguous-child-reference" })
    }

    @Test("SwiftPM product dependencies resolve renamed products and package aliases")
    func swiftPMProductResolutionUsesProductIdentityAndAlias() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                dependencies: [
                    .package(name: "AliasPkg", path: "Packages/FeatureWorkspace"),
                ],
                targets: [
                    .target(
                        name: "AppFeature",
                        dependencies: [.product(name: "FeatureKit", package: "AliasPkg")]
                    ),
                ]
            )
            """,
            to: rootURL.appendingPathComponent("Package.swift")
        )
        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "FeatureDisplay",
                products: [.library(name: "FeatureKit", targets: ["FeatureModule"])],
                targets: [.target(name: "FeatureModule")]
            )
            """,
            to: rootURL.appendingPathComponent("Packages/FeatureWorkspace/Package.swift")
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Packages/FeatureWorkspace/Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.isEmpty)
    }

    @Test("SwiftPM product dependencies resolve a unique external product when package is omitted")
    func swiftPMProductResolutionWithoutPackageFindsUniqueExternalProduct() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                dependencies: [
                    .package(name: "FeaturePkg", path: "Packages/FeatureWorkspace"),
                ],
                targets: [
                    .target(
                        name: "AppFeature",
                        dependencies: [.product(name: "FeatureKit")]
                    ),
                ]
            )
            """,
            to: rootURL.appendingPathComponent("Package.swift")
        )
        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "FeatureDisplay",
                products: [.library(name: "FeatureKit", targets: ["FeatureModule"])],
                targets: [.target(name: "FeatureModule")]
            )
            """,
            to: rootURL.appendingPathComponent("Packages/FeatureWorkspace/Package.swift")
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Packages/FeatureWorkspace/Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.isEmpty)
    }

    @Test("SwiftPM product dependencies skip missing-edge diagnostics when package omission is ambiguous")
    func swiftPMProductResolutionWithoutPackageSkipsFalseMissingEdgeOnAmbiguity() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                dependencies: [
                    .package(name: "AlphaPkg", path: "Packages/AlphaPkg"),
                    .package(name: "BetaPkg", path: "Packages/BetaPkg"),
                ],
                targets: [
                    .target(
                        name: "AppFeature",
                        dependencies: [.product(name: "FeatureKit")]
                    ),
                ]
            )
            """,
            to: rootURL.appendingPathComponent("Package.swift")
        )
        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "AlphaPkg",
                products: [.library(name: "FeatureKit", targets: ["AlphaFeatureModule"])],
                targets: [.target(name: "AlphaFeatureModule")]
            )
            """,
            to: rootURL.appendingPathComponent("Packages/AlphaPkg/Package.swift")
        )
        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "BetaPkg",
                products: [.library(name: "FeatureKit", targets: ["BetaFeatureModule"])],
                targets: [.target(name: "BetaFeatureModule")]
            )
            """,
            to: rootURL.appendingPathComponent("Packages/BetaPkg/Package.swift")
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var alpha: AlphaFeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct AlphaFeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Packages/AlphaPkg/Sources/AlphaFeatureModule/AlphaFeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(!report.issues.contains { $0.code == "hierarchy.module-edge-missing" })
    }

    @Test("Semantic child reference ambiguity is reported during hierarchy validation")
    func semanticChildReferenceAmbiguityFailsExplicitly() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }

            enum Alpha {
                @DIContainer
                struct FeatureContainer {
                    @Provide(.input) var config: Config
                }
            }

            enum Beta {
                @DIContainer
                struct FeatureContainer {
                    @Provide(.input) var config: Config
                }
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        let issue = report.issues.first(where: { $0.code == "hierarchy.ambiguous-child-reference" })
        #expect(issue != nil)
        #expect(issue?.metadata["resolutionSource"] == "semantic-resolver")
    }

    @Test("Unresolved child references fail explicitly during hierarchy validation")
    func unresolvedChildReferenceFailsExplicitly() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: MissingFeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        let issue = report.issues.first(where: { $0.code == "hierarchy.unresolved-child-reference" })
        #expect(issue != nil)
        #expect(issue?.metadata["resolutionState"] == "unresolved")
    }

    @Test("Invalid child references outside rooted hierarchies do not fail hierarchy validation")
    func invalidChildReferencesOutsideRootedHierarchiesAreIgnored() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature"),
                    .target(name: "ScratchFeature"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            @DIContainer
            struct ScratchContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: MissingFeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/ScratchFeature/ScratchContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(!report.issues.contains { $0.code == "hierarchy.unresolved-child-reference" })
        #expect(report.issues.isEmpty)
    }

    @Test("Reachable child containers still report invalid child references")
    func reachableChildContainersStillReportInvalidChildReferences() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }

            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var nested: MissingNestedContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.contains { $0.code == "hierarchy.unresolved-child-reference" })
    }

    @Test("Orphan components keep orphan diagnostics without child-reference failures")
    func orphanComponentsDoNotEmitChildReferenceFailures() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature"),
                    .target(name: "OrphanFeature"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct OrphanContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var nested: MissingNestedContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/OrphanFeature/OrphanContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.contains { $0.code == "hierarchy.orphan-component" })
        #expect(!report.issues.contains { $0.code == "hierarchy.unresolved-child-reference" })
    }

    @Test("SwiftPM package omission ignores same-package products when resolving dependency edges")
    func swiftPMProductResolutionWithoutPackageIgnoresSamePackageProducts() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                products: [.library(name: "FeatureKit", targets: ["LocalFeature"])],
                dependencies: [
                    .package(name: "RemoteFeaturePkg", path: "Packages/RemoteFeature"),
                ],
                targets: [
                    .target(name: "AppFeature", dependencies: [.product(name: "FeatureKit")]),
                    .target(name: "LocalFeature"),
                ]
            )
            """,
            to: rootURL.appendingPathComponent("Package.swift")
        )
        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "RemoteFeatureDisplay",
                products: [.library(name: "FeatureKit", targets: ["RemoteFeatureModule"])],
                targets: [.target(name: "RemoteFeatureModule")]
            )
            """,
            to: rootURL.appendingPathComponent("Packages/RemoteFeature/Package.swift")
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            struct PlaceholderFeature {}
            """,
            to: rootURL.appendingPathComponent("Sources/LocalFeature/Placeholder.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Packages/RemoteFeature/Sources/RemoteFeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.isEmpty)
    }

    @Test("Hierarchy validation accepts semantically equivalent input types")
    func hierarchyValidationUsesSemanticTypeEqualityForInputs() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(name: "FeatureModule"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            struct Config {}

            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            typealias FeatureConfig = Config

            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: FeatureConfig
            }
            """,
            to: rootURL.appendingPathComponent("Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.isEmpty)
    }

    @Test("Hierarchy validation rejects ambiguous semantic input matches even when raw spellings match")
    func hierarchyValidationRejectsAmbiguousSemanticInputMatches() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(name: "FeatureModule"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            enum AppFeature {
                struct Config {}
            }

            typealias Config = AppFeature.Config

            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            enum FeatureModule {
                struct Config {}
            }

            typealias Config = FeatureModule.Config

            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.contains { $0.code == "hierarchy.unsatisfied-dependency" })
    }

    @Test("Hierarchy validation keeps raw spelling fallback for external input types")
    func hierarchyValidationFallsBackToRawEqualityForExternalInputTypes() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(name: "FeatureModule"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var url: URL
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var url: URL
            }
            """,
            to: rootURL.appendingPathComponent("Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.isEmpty)
    }

    @Test("Qualified hierarchy and dependency attributes still participate in validation")
    func qualifiedHierarchyAttributesStillParticipateInValidation() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(name: "FeatureModule"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            struct ParentConfig {}

            @InnoDI.DIHierarchyRoot
            @InnoDI.DIContainer
            struct AppContainer {
                @InnoDI.Provide(.input) var config: ParentConfig
                @InnoDI.SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            struct ChildConfig {}

            @InnoDI.DIComponent
            @InnoDI.DIContainer
            struct FeatureContainer {
                @InnoDI.Provide(.input) var config: ChildConfig
            }
            """,
            to: rootURL.appendingPathComponent("Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.contains { $0.code == "hierarchy.unsatisfied-dependency" })
    }

    @Test("Foreign qualified hierarchy and dependency attributes are ignored during validation collection")
    func foreignQualifiedHierarchyAttributesAreIgnoredByValidation() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(name: "FeatureModule"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            struct Config {}

            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @OtherDI.SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            struct Config {}

            @OtherDI.DIComponent
            @OtherDI.DIContainer
            struct FeatureContainer {
                @OtherDI.Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.isEmpty)
    }

    @Test("SwiftPM string literal dependencies resolve unique external products")
    func swiftPMStringLiteralDependencyResolvesExternalProduct() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                dependencies: [
                    .package(name: "FeaturePkg", path: "Packages/FeatureWorkspace"),
                ],
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureKit"]),
                ]
            )
            """,
            to: rootURL.appendingPathComponent("Package.swift")
        )
        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "FeatureDisplay",
                products: [.library(name: "FeatureKit", targets: ["FeatureModule"])],
                targets: [.target(name: "FeatureModule")]
            )
            """,
            to: rootURL.appendingPathComponent("Packages/FeatureWorkspace/Package.swift")
        )

        try writeSource(
            """
            struct Config {}

            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Packages/FeatureWorkspace/Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(!report.issues.contains { $0.code == "hierarchy.module-edge-missing" })
        #expect(report.issues.isEmpty)
    }

    @Test("SwiftPM byName dependencies resolve unique external products")
    func swiftPMByNameDependencyResolvesExternalProduct() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                dependencies: [
                    .package(name: "FeaturePkg", path: "Packages/FeatureWorkspace"),
                ],
                targets: [
                    .target(name: "AppFeature", dependencies: [.byName(name: "FeatureKit")]),
                ]
            )
            """,
            to: rootURL.appendingPathComponent("Package.swift")
        )
        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "FeatureDisplay",
                products: [.library(name: "FeatureKit", targets: ["FeatureModule"])],
                targets: [.target(name: "FeatureModule")]
            )
            """,
            to: rootURL.appendingPathComponent("Packages/FeatureWorkspace/Package.swift")
        )

        try writeSource(
            """
            struct Config {}

            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Packages/FeatureWorkspace/Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(!report.issues.contains { $0.code == "hierarchy.module-edge-missing" })
        #expect(report.issues.isEmpty)
    }

    @Test("SwiftPM target sources are resolved relative to the target directory")
    func swiftPMExplicitSourcesUseTargetDirectoryAsBaseURL() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(
                        name: "FeatureModule",
                        path: "FeatureSources",
                        sources: ["Components/**"]
                    ),
                ]
            )
            """,
            to: rootURL.appendingPathComponent("Package.swift")
        )

        try writeSource(
            """
            struct Config {}

            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )
        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("FeatureSources/Components/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.isEmpty)
    }

    @Test("Duplicate bindings emit a structured hierarchy issue")
    func duplicateBindingsEmitStructuredIssue() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(name: "FeatureModule"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            struct Config {}

            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var firstConfig: Config
                @Provide(.input) var secondConfig: Config
                @SubContainer(
                    scope: .shared,
                    bindings: [
                        (child: \\.config, parent: \\.firstConfig),
                        (child: \\.config, parent: \\.secondConfig),
                    ]
                )
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )

        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        let issue = try #require(report.issues.first { $0.code == "hierarchy.duplicate-binding-mapping" })
        #expect(issue.location.filePath.hasSuffix("Sources/AppFeature/AppContainer.swift"))
        #expect(issue.location.line == 12)
        #expect(issue.location.column == 21)
        let firstNote = try #require(issue.notes.first)
        let firstLocation = try #require(firstNote.location)
        #expect(firstLocation.filePath.hasSuffix("Sources/AppFeature/AppContainer.swift"))
        #expect(firstLocation.line == 11)
        #expect(firstLocation.column == 21)
    }

    @Test("Duplicate with dependencies emit a structured hierarchy issue")
    func duplicateWithDependenciesEmitStructuredIssue() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(name: "FeatureModule"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            struct Config {}

            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared, with: [\\.config, \\.config])
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )

        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        let issue = try #require(report.issues.first { $0.code == "hierarchy.duplicate-with-dependency" })
        #expect(issue.location.filePath.hasSuffix("Sources/AppFeature/AppContainer.swift"))
        #expect(issue.location.line == 7)
        #expect(issue.location.column == 52)
        let firstNote = try #require(issue.notes.first)
        let firstLocation = try #require(firstNote.location)
        #expect(firstLocation.filePath.hasSuffix("Sources/AppFeature/AppContainer.swift"))
        #expect(firstLocation.line == 7)
        #expect(firstLocation.column == 42)
    }

    @Test("withNames dependencies participate in hierarchy input validation")
    func withNamesDependenciesParticipateInHierarchyInputValidation() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(name: "FeatureModule"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            struct Config {}
            struct Extra {}

            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @Provide(.input) var extra: Extra
                @SubContainer(scope: .shared, withNames: ["extra"])
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )

        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        let issue = try #require(report.issues.first { $0.code == "hierarchy.unsatisfied-dependency" })
        #expect(issue.metadata["childInputName"] == "config")
    }

    @Test("Explicit empty withNames does not fall back to implicit hierarchy wiring")
    func explicitEmptyWithNamesDoesNotFallbackToImplicitHierarchyWiring() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(name: "FeatureModule"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            struct Config {}

            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared, withNames: [])
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )

        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        let issue = try #require(report.issues.first { $0.code == "hierarchy.unsatisfied-dependency" })
        #expect(issue.metadata["childInputName"] == "config")
    }

    @Test("Explicit empty withNames accepts inputless child components")
    func explicitEmptyWithNamesAcceptsInputlessChildComponents() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(name: "FeatureModule"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            struct Config {}

            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared, withNames: [])
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )

        try writeSource(
            """
            struct FeatureService {}

            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.shared, factory: FeatureService(), concrete: true)
                var service: FeatureService
            }
            """,
            to: rootURL.appendingPathComponent("Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.isEmpty)
    }

    @Test("Duplicate withNames dependencies use string literal locations")
    func duplicateWithNamesDependenciesUseStringLiteralLocations() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(name: "FeatureModule"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            struct Config {}

            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared, withNames: ["config", "config"])
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )

        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: Config
            }
            """,
            to: rootURL.appendingPathComponent("Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        let issue = try #require(report.issues.first { $0.code == "hierarchy.duplicate-with-dependency" })
        #expect(issue.message.contains("with:/withNames:"))
        #expect(issue.location.filePath.hasSuffix("Sources/AppFeature/AppContainer.swift"))
        #expect(issue.location.line == 7)
        #expect(issue.location.column == 57)
        let firstNote = try #require(issue.notes.first)
        let firstLocation = try #require(firstNote.location)
        #expect(firstLocation.filePath.hasSuffix("Sources/AppFeature/AppContainer.swift"))
        #expect(firstLocation.line == 7)
        #expect(firstLocation.column == 47)
    }

    @Test("Bindings type mismatches point at the mapped parent key-path location")
    func bindingsTypeMismatchUsesParentKeyPathLocation() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature", dependencies: ["FeatureModule"]),
                    .target(name: "FeatureModule"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            struct ParentConfig {}
            struct ChildConfig {}

            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var parentConfig: ParentConfig
                @SubContainer(
                    scope: .shared,
                    bindings: [
                        (child: \\.config, parent: \\.parentConfig),
                    ]
                )
                var feature: FeatureContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )

        try writeSource(
            """
            @DIComponent
            @DIContainer
            struct FeatureContainer {
                @Provide(.input) var config: ChildConfig
            }
            """,
            to: rootURL.appendingPathComponent("Sources/FeatureModule/FeatureContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        let issue = try #require(report.issues.first { issue in
            issue.code == "hierarchy.unsatisfied-dependency"
                && issue.message.contains("types do not match")
        })
        #expect(issue.location.filePath.hasSuffix("Sources/AppFeature/AppContainer.swift"))
        #expect(issue.location.line == 11)
        #expect(issue.location.column == 39)
    }

    @Test("Self-loop subcontainers emit a hierarchy cycle issue")
    func selfLoopSubcontainerEmitsCycleIssue() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            struct Config {}

            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared)
                var app: AppContainer
            }
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppContainer.swift")
        )

        let report = try WorkspaceHierarchyBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.contains { $0.code == "hierarchy.component-cycle" })
    }

    @Test("Workspace module graph ignores manifests under hidden root directories")
    func workspaceModuleGraphIgnoresHiddenRootManifests() throws {
        let rootURL = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeSwiftPMManifest(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "Workspace",
                targets: [
                    .target(name: "AppFeature"),
                ]
            )
            """,
            to: rootURL
        )

        try writeSource(
            """
            struct AppFeature {}
            """,
            to: rootURL.appendingPathComponent("Sources/AppFeature/AppFeature.swift")
        )

        try writeSource(
            """
            // swift-tools-version: 6.2
            import PackageDescription

            let package = Package(
                name: "HiddenWorkspace",
                targets: [
                    .target(name: "HiddenFeature"),
                ]
            )
            """,
            to: rootURL.appendingPathComponent(".build/artifacts/Package.swift")
        )

        let snapshot = try ModuleGraphProvider.snapshot(rootPath: rootURL.path(percentEncoded: false))

        #expect(snapshot.modules.map(\.name).sorted() == ["AppFeature"])
    }

    @Test("Package identity normalization preserves embedded .git and trims only a suffix")
    func packageIdentityNormalizationTrimsOnlySuffix() {
        #expect(normalizePackageIdentity("signal.git.backup") == "signal.git.backup")
        #expect(normalizePackageIdentity("signal.git.backup.git") == "signal.git.backup")
        #expect(normalizePackageIdentity(" Signal.Git.Backup.GIT \n") == "signal.git.backup")
    }
}

private func makeTemporaryWorkspaceRoot() throws -> URL {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-WorkspaceHierarchy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    return rootURL
}

private func writeSwiftPMManifest(_ contents: String, to rootURL: URL) throws {
    try contents.write(
        to: rootURL.appendingPathComponent("Package.swift"),
        atomically: true,
        encoding: .utf8
    )
}

private func writeSource(_ contents: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: url, atomically: true, encoding: .utf8)
}
