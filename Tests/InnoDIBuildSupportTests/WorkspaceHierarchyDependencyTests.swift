import Foundation
import Testing
import InnoDITestSupport

@testable import InnoDIBuildSupport

/// Dependency discovery and explicit wiring contracts for hierarchy validation.
extension WorkspaceHierarchyBuildValidatorTests {
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

    @Test("with dependencies participate in hierarchy input validation")
    func withDependenciesParticipateInHierarchyInputValidation() throws {
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
                @SubContainer(scope: .shared, with: [\\.extra])
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

    @Test("Explicit empty with does not fall back to implicit hierarchy wiring")
    func explicitEmptyWithDoesNotFallbackToImplicitHierarchyWiring() throws {
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
                @SubContainer(scope: .shared, with: [])
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

    @Test("Explicit empty with accepts inputless child components")
    func explicitEmptyWithAcceptsInputlessChildComponents() throws {
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
                @SubContainer(scope: .shared, with: [])
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
                @Provide(.shared, factory: FeatureService())
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

    @Test("Non-literal with reports invalid same-name wiring without implicit fallback")
    func nonLiteralWithReportsInvalidSameNameWiring() throws {
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

            let dependencyKeyPaths = [\\AppContainer.config]

            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared, with: dependencyKeyPaths)
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

        let issue = try #require(report.issues.first { $0.code == "hierarchy.invalid-same-name-wiring" })
        #expect(issue.metadata["label"] == "with")
        #expect(issue.location.filePath.hasSuffix("Sources/AppFeature/AppContainer.swift"))
        #expect(report.issues.allSatisfy { $0.code != "hierarchy.unsatisfied-dependency" })
    }

    @Test("Malformed bindings reports invalid bindings without implicit fallback")
    func malformedBindingsReportsInvalidBindings() throws {
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

            let explicitBindings = [(child: \\FeatureContainer.config, parent: \\AppContainer.config)]

            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared, bindings: explicitBindings)
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

        let issue = try #require(report.issues.first { $0.code == "hierarchy.invalid-bindings" })
        #expect(issue.location.filePath.hasSuffix("Sources/AppFeature/AppContainer.swift"))
        #expect(report.issues.allSatisfy { $0.code != "hierarchy.unsatisfied-dependency" })
    }

    @Test("Malformed binding tuple labels report invalid bindings without implicit fallback")
    func malformedBindingTupleLabelsReportInvalidBindings() throws {
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
                @SubContainer(
                    scope: .shared,
                    bindings: [(child: \\.config, parent: \\.config, extra: \\.config)]
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

        let issue = try #require(report.issues.first { $0.code == "hierarchy.invalid-bindings" })
        #expect(issue.location.filePath.hasSuffix("Sources/AppFeature/AppContainer.swift"))
        #expect(report.issues.allSatisfy { $0.code != "hierarchy.unsatisfied-dependency" })
    }

    @Test("Same-name wiring with bindings reports hierarchy conflict before binding resolution")
    func sameNameWiringWithBindingsReportsHierarchyConflict() throws {
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

            let dependencyKeyPaths = [\\AppContainer.config]

            @DIHierarchyRoot
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: Config
                @SubContainer(
                    scope: .shared,
                    with: dependencyKeyPaths,
                    bindings: [(child: \\.config, parent: \\.config)]
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

        let issue = try #require(report.issues.first { $0.code == "hierarchy.bindings-conflicts-with-with" })
        #expect(issue.metadata["label"] == "with")
        #expect(report.issues.allSatisfy { $0.code != "hierarchy.invalid-same-name-wiring" })
        #expect(report.issues.allSatisfy { $0.code != "hierarchy.unsatisfied-dependency" })
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
