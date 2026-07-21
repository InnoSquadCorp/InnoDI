import Foundation
import InnoDIWorkspaceAnalysis
import SwiftParser
import Testing

@testable import InnoDIBuildSupport

@Suite("Generated qualifier full-source preflight")
struct GeneratedQualifierBuildValidatorTests {
    @Test("Plain containers ignore unused same-target qualifier shadows")
    func plainContainerTopLevelShadowsAreAllowed() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Container.swift",
                source: """
                @DIContainer
                struct AppContainer {
                    @Provide(.input) var value: Int
                }
                """
            ),
            .init(
                path: "Sources/App/Shadows.swift",
                source: """
                struct Swift {}
                enum _Concurrency {}
                let InnoDI = 0
                """
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.isEmpty)
    }

    @Test("Container qualifier checks follow emitted feature support")
    func containerFeatureQualifierShadowsAreRejected() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Container.swift",
                source: """
                @DIContainer(mainActor: true)
                struct AppContainer {
                    @Provide(.transient, factory: { 42 })
                    var dependency: Int

                    @Provide(factory: { (dependency: Provider<Int>) in
                        dependency()
                    })
                    var value: Int

                    @Provide(asyncFactory: { () async -> String in "ready" })
                    var asyncValue: String
                }
                """
            ),
            .init(
                path: "Sources/App/Shadows.swift",
                source: """
                struct Swift {}
                enum _Concurrency {}
                let InnoDI = 0
                """
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.count == 3)
        #expect(Set(report.issues.compactMap { $0.metadata["qualifier"] }) == [
            "InnoDI", "Swift", "_Concurrency",
        ])
        #expect(report.issues.allSatisfy {
            $0.metadata["lookupScopes"] == "same-target-top-level"
        })
    }

    @Test("Hierarchy extension qualifiers require a type namespace")
    func hierarchyQualifierNamespaceIsTypeOnly() {
        for (shadow, expectedCount) in [
            ("let InnoDI = 0", 0),
            ("struct InnoDI {}", 1),
        ] {
            let snapshot = makeSnapshot([
                .init(
                    path: "Sources/App/Container.swift",
                    source: """
                    @DIComponent
                    @DIContainer
                    struct AppContainer {
                        @Provide(.input) var value: Int
                    }
                    """
                ),
                .init(
                    path: "Sources/App/Shadow.swift",
                    source: shadow
                ),
            ])

            let report = GeneratedQualifierBuildValidator.validate(
                snapshot: snapshot
            )

            #expect(
                report.issues.count == expectedCount,
                Comment(rawValue: shadow)
            )
        }
    }

    @Test("Extension-only qualifiers ignore member and inheritance lookup")
    func hierarchyQualifierDoesNotInspectMemberScopes() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Container.swift",
                source: """
                class FeatureHost: ExternalBase {
                    struct InnoDI {}

                    @DIComponent
                    @DIContainer
                    struct Container {
                        @Provide(.input) var value: Int
                    }
                }
                """
            ),
            .init(
                path: "Sources/App/Extensions.swift",
                source: """
                extension FeatureHost.Container {
                    typealias InnoDI = Int
                }
                """
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.isEmpty)
    }

    @Test("Container qualifiers include enclosing and matching extension members")
    func containerEnclosingAndExtensionShadowsAreRejected() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Container.swift",
                source: """
                struct FeatureHost {
                    @DIContainer(mainActor: true)
                    struct AppContainer {
                        @Provide(.transient, factory: { 1 })
                        var dependency: Int

                        @Provide(factory: { (dependency: Provider<Int>) in
                            dependency()
                        })
                        var value: Int

                        @Provide(asyncFactory: { () async -> Int in 2 })
                        var asyncValue: Int
                    }

                    struct Swift {}
                }
                """
            ),
            .init(
                path: "Sources/App/Extensions.swift",
                source: """
                extension FeatureHost {
                    typealias _Concurrency = Int
                }

                extension FeatureHost.AppContainer {
                    static let InnoDI = 0
                }
                """
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.count == 3)
        #expect(Set(report.issues.compactMap { $0.metadata["qualifier"] }) == [
            "InnoDI", "Swift", "_Concurrency",
        ])
        #expect(Set(report.issues.compactMap {
            $0.metadata["lookupScopes"]
        }) == [
            "enclosing-nominal-member",
            "matching-extension-member",
        ])
    }

    @Test("Matching extensions inherit access and resolve self-module qualification")
    func matchingExtensionEffectiveAccessIsRespected() {
        let appID = WorkspaceTargetID.swiftPM(
            packageIdentity: "root-package",
            moduleName: "App"
        )
        let manifest = WorkspaceAnalysisManifest(
            rootPackageIdentity: "root-package",
            rootPackageDirectory: "/workspace",
            primaryTargetID: appID,
            targets: [
                makeTarget(
                    id: appID,
                    packageIdentity: "root-package",
                    moduleName: "App",
                    role: .primary
                ),
            ]
        )
        let snapshot = makeSnapshot(
            [
                .init(
                    path: "Sources/App/Container.swift",
                    source: """
                    @DIContainer(mainActor: true)
                    struct AppContainer {
                        @Provide(.transient, factory: { 1 })
                        var dependency: Int

                        @Provide(factory: { (dependency: Provider<Int>) in
                            dependency()
                        })
                        var value: Int

                        @Provide(asyncFactory: { () async -> String in "" })
                        var asyncValue: String
                    }
                    """,
                    targetID: appID
                ),
                .init(
                    path: "Sources/App/PrivateExtension.swift",
                    source: """
                    private extension AppContainer {
                        struct Swift {}
                    }
                    """,
                    targetID: appID
                ),
                .init(
                    path: "Sources/App/FileprivateExtension.swift",
                    source: """
                    fileprivate extension AppContainer {
                        struct _Concurrency {}
                    }
                    """,
                    targetID: appID
                ),
                .init(
                    path: "Sources/App/QualifiedExtension.swift",
                    source: """
                    extension App.AppContainer {
                        static let InnoDI = 0
                    }

                    typealias ContainerAlias = (App.AppContainer)

                    extension (ContainerAlias) {
                        struct Swift {}
                    }
                    """,
                    targetID: appID
                ),
            ],
            manifest: manifest
        )

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.count == 2)
        #expect(Set(report.issues.compactMap { $0.metadata["qualifier"] }) == [
            "InnoDI", "Swift",
        ])
        #expect(report.issues.allSatisfy {
            $0.metadata["lookupScopes"] == "matching-extension-member"
        })
    }

    @Test("Bridge qualifiers include same-target enclosing and extension declarations")
    func bridgeFullSourceShadowsAreRejected() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Bridge.swift",
                source: """
                struct FeatureHost {
                    @DIEnvironmentBridge([])
                    struct BridgeContainer {
                        struct SwiftUI {}
                    }

                    struct Swift {}
                }

                struct SwiftUI {}
                """
            ),
            .init(
                path: "Sources/App/Bridge+Shadows.swift",
                source: """
                extension FeatureHost {
                    typealias InnoDISwiftUI = Int
                }

                extension FeatureHost.BridgeContainer {
                    typealias SwiftUI = Int
                }
                """
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.count == 3)
        #expect(Set(report.issues.map(\.code)) == [
            "swiftui.environment-bridge-reserved-module-name",
        ])
        #expect(Set(report.issues.compactMap { $0.metadata["qualifier"] }) == [
            "Swift", "SwiftUI",
        ])
    }

    @Test("Bridge extension qualifier checks only file-scope visibility")
    func bridgeExtensionQualifierScopeIsRespected() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Bridge.swift",
                source: """
                struct Host {
                    @DIEnvironmentBridge([])
                    struct Bridge {}

                    struct InnoDISwiftUI {}
                }
                """
            ),
            .init(
                path: "Sources/App/Shadows.swift",
                source: "struct InnoDISwiftUI {}"
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.count == 1)
        #expect(report.issues.first?.metadata["qualifier"] == "InnoDISwiftUI")
        #expect(
            report.issues.first?.metadata["lookupScopes"]
                == "same-target-top-level"
        )
    }

    @Test("Bridge qualifiers include inherited superclass members")
    func directBridgeSuperclassShadowsAreRejected() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Bridge.swift",
                source: """
                class BaseBridge {
                    struct Swift {}
                    struct SwiftUI {}
                    struct InnoDISwiftUI {}
                }

                @DIEnvironmentBridge([])
                final class Bridge: BaseBridge {}
                """
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.count == 2)
        #expect(Set(report.issues.compactMap { $0.metadata["qualifier"] }) == [
            "Swift", "SwiftUI",
        ])
        #expect(report.issues.allSatisfy {
            $0.metadata["lookupScopes"] == "inherited-superclass-member"
        })
    }

    @Test("Plain containers ignore unused inherited qualifier shadows")
    func plainNestedContainerSuperclassShadowsAreAllowed() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Container.swift",
                source: """
                class BaseHost {
                    struct Swift {}
                    struct _Concurrency {}
                    static let InnoDI = 0
                }

                final class FeatureHost: BaseHost {
                    @DIContainer
                    struct Container {
                        @Provide(.input) var value: Int
                    }
                }
                """
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.isEmpty)
    }

    @Test("Emitted container qualifiers include an enclosing superclass")
    func featureContainerSuperclassShadowsAreRejected() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Container.swift",
                source: """
                class BaseHost {
                    struct Swift {}
                    struct _Concurrency {}
                    static let InnoDI = 0
                }

                final class FeatureHost: BaseHost {
                    @DIContainer(mainActor: true)
                    struct Container {
                        @Provide(.transient, factory: { 1 })
                        var dependency: Int

                        @Provide(factory: { (dependency: Provider<Int>) in
                            dependency()
                        })
                        var value: Int

                        @Provide(asyncFactory: { () async -> Int in 2 })
                        var asyncValue: Int
                    }
                }
                """
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.count == 3)
        #expect(Set(report.issues.compactMap { $0.metadata["qualifier"] }) == [
            "InnoDI", "Swift", "_Concurrency",
        ])
        #expect(report.issues.allSatisfy {
            $0.metadata["lookupScopes"] == "inherited-superclass-member"
        })
    }

    @Test("Known protocol-only and shadow-free class inheritance are safe")
    func knownSafeInheritanceDoesNotFailClosed() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Bridge.swift",
                source: """
                protocol BridgeProtocol {}
                class SafeBase {}

                @DIEnvironmentBridge([])
                final class ProtocolBridge: BridgeProtocol {}

                @DIEnvironmentBridge([])
                final class ClassBridge: SafeBase {}
                """
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.isEmpty)
    }

    @Test("Superclass chains resolve through aliases and matching extensions")
    func multiHopAliasedSuperclassShadowsAreRejected() {
        let appID = WorkspaceTargetID.swiftPM(
            packageIdentity: "root-package",
            moduleName: "App"
        )
        let manifest = WorkspaceAnalysisManifest(
            rootPackageIdentity: "root-package",
            rootPackageDirectory: "/workspace",
            primaryTargetID: appID,
            targets: [
                makeTarget(
                    id: appID,
                    packageIdentity: "root-package",
                    moduleName: "App",
                    role: .primary
                ),
            ]
        )
        let snapshot = makeSnapshot(
            [
                .init(
                    path: "Sources/App/Hierarchy.swift",
                    source: """
                    class RootBase {}

                    extension RootBase {
                        struct SwiftUI {}
                    }

                    typealias RootAlias = (App.RootBase)
                    class MiddleBase: RootAlias {}
                    typealias MiddleAlias = MiddleBase

                    @DIEnvironmentBridge([])
                    final class Bridge: MiddleAlias {}
                    """,
                    targetID: appID
                ),
            ],
            manifest: manifest
        )

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.count == 1)
        #expect(report.issues.first?.metadata["qualifier"] == "SwiftUI")
        #expect(
            report.issues.first?.metadata["lookupScopes"]
                == "inherited-superclass-member"
        )
    }

    @Test("Unresolved first inheritance fails closed")
    func unresolvedSuperclassIsRejected() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Bridge.swift",
                source: """
                @DIEnvironmentBridge([])
                final class Bridge: ExternalBase {}
                """
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.count == 1)
        #expect(
            report.issues.first?.code
                == "generated-qualifier.inheritance-unverifiable"
        )
        #expect(report.issues.first?.metadata["class"] == "Bridge")
        #expect(report.issues.first?.metadata["inheritedType"] == "ExternalBase")
        #expect(report.issues.first?.metadata["resolutionState"] == "unresolved")
    }

    @Test("Ambiguous first inheritance fails closed")
    func ambiguousSuperclassIsRejected() {
        let appID = WorkspaceTargetID.swiftPM(
            packageIdentity: "root-package",
            moduleName: "App"
        )
        let firstID = WorkspaceTargetID.swiftPM(
            packageIdentity: "first-package",
            moduleName: "FirstBaseKit"
        )
        let secondID = WorkspaceTargetID.swiftPM(
            packageIdentity: "second-package",
            moduleName: "SecondBaseKit"
        )
        let manifest = WorkspaceAnalysisManifest(
            rootPackageIdentity: "root-package",
            rootPackageDirectory: "/workspace",
            primaryTargetID: appID,
            targets: [
                makeTarget(
                    id: appID,
                    packageIdentity: "root-package",
                    moduleName: "App",
                    role: .primary,
                    dependencies: [firstID, secondID]
                ),
                makeTarget(
                    id: firstID,
                    packageIdentity: "first-package",
                    moduleName: "FirstBaseKit"
                ),
                makeTarget(
                    id: secondID,
                    packageIdentity: "second-package",
                    moduleName: "SecondBaseKit"
                ),
            ]
        )
        let snapshot = makeSnapshot(
            [
                .init(
                    path: "Sources/App/Bridge.swift",
                    source: """
                    import FirstBaseKit
                    import SecondBaseKit

                    @DIEnvironmentBridge([])
                    final class Bridge: BaseBridge {}
                    """,
                    targetID: appID
                ),
                .init(
                    path: "Sources/FirstBaseKit/Base.swift",
                    source: "open class BaseBridge {}",
                    targetID: firstID
                ),
                .init(
                    path: "Sources/SecondBaseKit/Base.swift",
                    source: "open class BaseBridge {}",
                    targetID: secondID
                ),
            ],
            manifest: manifest
        )

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.count == 1)
        #expect(
            report.issues.first?.code
                == "generated-qualifier.inheritance-unverifiable"
        )
        #expect(report.issues.first?.metadata["resolutionState"] == "ambiguous")
    }

    @Test("Private inherited members stay hidden and fileprivate stays file-scoped")
    func inheritedMemberAccessIsRespected() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/CrossFileBase.swift",
                source: """
                class CrossFileBase {
                    private struct Swift {}
                    fileprivate struct SwiftUI {}
                }
                """
            ),
            .init(
                path: "Sources/App/CrossFileBridge.swift",
                source: """
                @DIEnvironmentBridge([])
                final class CrossFileBridge: CrossFileBase {}
                """
            ),
            .init(
                path: "Sources/App/SameFileBridge.swift",
                source: """
                class SameFileBase {
                    private struct Swift {}
                    fileprivate struct SwiftUI {}
                }

                @DIEnvironmentBridge([])
                final class SameFileBridge: SameFileBase {}
                """
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.count == 1)
        #expect(report.issues.first?.metadata["qualifier"] == "SwiftUI")
        #expect(
            report.issues.first?.location.filePath
                == "/workspace/Sources/App/SameFileBridge.swift"
        )
    }

    @Test("Imported source-visible superclasses are validated")
    func dependencySuperclassShadowsAreRejected() {
        let appID = WorkspaceTargetID.swiftPM(
            packageIdentity: "root-package",
            moduleName: "App"
        )
        let baseID = WorkspaceTargetID.swiftPM(
            packageIdentity: "base-package",
            moduleName: "BaseKit"
        )
        let manifest = WorkspaceAnalysisManifest(
            rootPackageIdentity: "root-package",
            rootPackageDirectory: "/workspace",
            primaryTargetID: appID,
            targets: [
                makeTarget(
                    id: appID,
                    packageIdentity: "root-package",
                    moduleName: "App",
                    role: .primary,
                    dependencies: [baseID]
                ),
                makeTarget(
                    id: baseID,
                    packageIdentity: "base-package",
                    moduleName: "BaseKit"
                ),
            ]
        )
        let snapshot = makeSnapshot(
            [
                .init(
                    path: "Sources/App/Bridge.swift",
                    source: """
                    import BaseKit

                    @DIEnvironmentBridge([])
                    final class Bridge: BaseKit.BaseBridge {}
                    """,
                    targetID: appID
                ),
                .init(
                    path: "Sources/BaseKit/Base.swift",
                    source: """
                    open class BaseBridge {
                        public struct SwiftUI {}
                    }
                    """,
                    targetID: baseID
                ),
            ],
            manifest: manifest
        )

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.count == 1)
        #expect(report.issues.first?.metadata["qualifier"] == "SwiftUI")
        #expect(
            report.issues.first?.metadata["lookupScopes"]
                == "inherited-superclass-member"
        )
    }

    @Test("Bridge rejects direct extension, extension-nested, and local targets")
    func bridgeUnsupportedContextsAreRejected() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Unsupported.swift",
                source: """
                struct Host {}

                @DIEnvironmentBridge([])
                extension Host {}

                extension Host {
                    @DIEnvironmentBridge([])
                    struct NestedBridge {}
                }

                func makeBridge() {
                    @DIEnvironmentBridge([])
                    struct LocalBridge {}
                }

                var accessorBridge: Int {
                    @DIEnvironmentBridge([])
                    struct AccessorBridge {}
                    return 0
                }

                do {
                    @DIEnvironmentBridge([])
                    struct ScriptBridge {}
                }
                """
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.count == 5)
        #expect(report.issues.filter {
            $0.code
                == "swiftui.environment-bridge-extension-context-unsupported"
        }.count == 2)
        #expect(report.issues.filter {
            $0.code
                == "swiftui.environment-bridge-local-declaration-unsupported"
        }.count == 3)
        #expect(report.issues.contains {
            $0.metadata["localContext"] == "function 'makeBridge'"
        })
        #expect(report.issues.contains {
            $0.metadata["localContext"] == "an accessor"
        })
        #expect(report.issues.contains {
            $0.metadata["localContext"] == "a code block"
        })
    }

    @Test("Attached-macro-owned qualifier scopes are not diagnosed twice")
    func macroSiteQualifierDiagnosticsRemainMacroOwned() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/MacroOwned.swift",
                source: """
                struct InnoDI {
                    @DIContainer
                    struct AppContainer {
                        typealias _Concurrency = Int
                        static let InnoDI = 0
                        @Provide(.input) var value: Int
                    }
                }

                @DIEnvironmentBridge([])
                struct SwiftUI {
                    typealias Swift = Int
                    typealias InnoDISwiftUI = Int
                }
                """
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.isEmpty)
    }

    @Test("Manifest scope uses only primary sites and actually imported dependency declarations")
    func manifestScopeAndDependencyVisibilityAreRespected() throws {
        let appID = WorkspaceTargetID.swiftPM(
            packageIdentity: "root-package",
            moduleName: "App"
        )
        let shadowID = WorkspaceTargetID.swiftPM(
            packageIdentity: "shadow-package",
            moduleName: "ShadowKit"
        )
        let samePackageID = WorkspaceTargetID.swiftPM(
            packageIdentity: "root-package",
            moduleName: "SamePackageKit"
        )
        let unusedID = WorkspaceTargetID.swiftPM(
            packageIdentity: "unused-package",
            moduleName: "UnusedKit"
        )
        let targets = [
            makeTarget(
                id: appID,
                packageIdentity: "root-package",
                moduleName: "App",
                role: .primary,
                dependencies: [shadowID, samePackageID, unusedID]
            ),
            makeTarget(
                id: shadowID,
                packageIdentity: "shadow-package",
                moduleName: "ShadowKit"
            ),
            makeTarget(
                id: samePackageID,
                packageIdentity: "root-package",
                moduleName: "SamePackageKit"
            ),
            makeTarget(
                id: unusedID,
                packageIdentity: "unused-package",
                moduleName: "UnusedKit"
            ),
        ]
        let manifest = WorkspaceAnalysisManifest(
            rootPackageIdentity: "root-package",
            rootPackageDirectory: "/workspace",
            primaryTargetID: appID,
            targets: targets
        )
        let snapshot = makeSnapshot(
            [
                .init(
                    path: "Sources/App/Container.swift",
                    source: """
                    import struct ShadowKit.Swift
                    import SamePackageKit

                    @DIContainer(mainActor: true)
                    struct AppContainer {
                        @Provide(.input) var value: Int

                        @Provide(asyncFactory: { () async -> Int in 1 })
                        var asyncValue: Int
                    }
                    """,
                    targetID: appID
                ),
                .init(
                    path: "Sources/ShadowKit/Shadows.swift",
                    source: """
                    public struct Swift {}
                    public struct InnoDI {}
                    package struct _Concurrency {}

                    @DIContainer
                    struct DependencyContainer {}
                    """,
                    targetID: shadowID
                ),
                .init(
                    path: "Sources/SamePackageKit/Shadows.swift",
                    source: "package struct _Concurrency {}",
                    targetID: samePackageID
                ),
                .init(
                    path: "Sources/UnusedKit/Shadows.swift",
                    source: "public struct InnoDI {}",
                    targetID: unusedID
                ),
            ],
            manifest: manifest
        )

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.count == 2)
        #expect(Set(report.issues.compactMap { $0.metadata["qualifier"] }) == [
            "Swift", "_Concurrency",
        ])
        #expect(report.issues.allSatisfy {
            $0.metadata["lookupScopes"] == "visible-dependency"
        })
    }

    @Test("Dependency visibility respects testable and SPI imports")
    func testableAndSPIImportsAreRespected() {
        let appID = WorkspaceTargetID.swiftPM(
            packageIdentity: "root-package",
            moduleName: "App"
        )
        let testSupportID = WorkspaceTargetID.swiftPM(
            packageIdentity: "test-support-package",
            moduleName: "TestSupportKit"
        )
        let spiID = WorkspaceTargetID.swiftPM(
            packageIdentity: "spi-package",
            moduleName: "SPIKit"
        )
        let hiddenSPIID = WorkspaceTargetID.swiftPM(
            packageIdentity: "hidden-spi-package",
            moduleName: "HiddenSPIKit"
        )
        let mismatchedSPIID = WorkspaceTargetID.swiftPM(
            packageIdentity: "mismatched-spi-package",
            moduleName: "MismatchedSPIKit"
        )
        let dependencyIDs = [
            testSupportID,
            spiID,
            hiddenSPIID,
            mismatchedSPIID,
        ]
        let manifest = WorkspaceAnalysisManifest(
            rootPackageIdentity: "root-package",
            rootPackageDirectory: "/workspace",
            primaryTargetID: appID,
            targets: [
                makeTarget(
                    id: appID,
                    packageIdentity: "root-package",
                    moduleName: "App",
                    role: .primary,
                    dependencies: dependencyIDs
                ),
                makeTarget(
                    id: testSupportID,
                    packageIdentity: "test-support-package",
                    moduleName: "TestSupportKit"
                ),
                makeTarget(
                    id: spiID,
                    packageIdentity: "spi-package",
                    moduleName: "SPIKit"
                ),
                makeTarget(
                    id: hiddenSPIID,
                    packageIdentity: "hidden-spi-package",
                    moduleName: "HiddenSPIKit"
                ),
                makeTarget(
                    id: mismatchedSPIID,
                    packageIdentity: "mismatched-spi-package",
                    moduleName: "MismatchedSPIKit"
                ),
            ]
        )
        let snapshot = makeSnapshot(
            [
                .init(
                    path: "Sources/App/Container.swift",
                    source: """
                    @testable import TestSupportKit
                    @_spi(GeneratedCode) import SPIKit
                    import HiddenSPIKit
                    @_spi(OtherGroup) import MismatchedSPIKit

                    @DIContainer(mainActor: true)
                    struct AppContainer {
                        @Provide(.input) var value: Int

                        @Provide(asyncFactory: { () async -> Int in 1 })
                        var asyncValue: Int
                    }
                    """,
                    targetID: appID
                ),
                .init(
                    path: "Sources/TestSupportKit/Shadows.swift",
                    source: """
                    struct Swift {}
                    @_spi(GeneratedCode) public let InnoDI = 0
                    """,
                    targetID: testSupportID
                ),
                .init(
                    path: "Sources/SPIKit/Shadows.swift",
                    source: """
                    @_spi(GeneratedCode) public enum _Concurrency {}
                    struct InnoDI {}
                    """,
                    targetID: spiID
                ),
                .init(
                    path: "Sources/HiddenSPIKit/Shadows.swift",
                    source: """
                    @_spi(GeneratedCode) public let InnoDI = 0
                    struct Swift {}
                    """,
                    targetID: hiddenSPIID
                ),
                .init(
                    path: "Sources/MismatchedSPIKit/Shadows.swift",
                    source: """
                    @_spi(GeneratedCode) public struct Swift {}
                    """,
                    targetID: mismatchedSPIID
                ),
            ],
            manifest: manifest
        )

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.count == 2)
        #expect(Set(report.issues.compactMap { $0.metadata["qualifier"] }) == [
            "Swift", "_Concurrency",
        ])
        #expect(report.issues.allSatisfy {
            $0.metadata["lookupScopes"] == "visible-dependency"
        })
    }

    @Test("Extension-nested containers remain declaration-matrix owned")
    func dependencyExtensionVisibilityDoesNotDuplicateUnsupportedSites() {
        let appID = WorkspaceTargetID.swiftPM(
            packageIdentity: "root-package",
            moduleName: "App"
        )
        let shadowID = WorkspaceTargetID.swiftPM(
            packageIdentity: "shadow-package",
            moduleName: "ShadowKit"
        )
        let manifest = WorkspaceAnalysisManifest(
            rootPackageIdentity: "root-package",
            rootPackageDirectory: "/workspace",
            primaryTargetID: appID,
            targets: [
                makeTarget(
                    id: appID,
                    packageIdentity: "root-package",
                    moduleName: "App",
                    role: .primary,
                    dependencies: [shadowID]
                ),
                makeTarget(
                    id: shadowID,
                    packageIdentity: "shadow-package",
                    moduleName: "ShadowKit"
                ),
            ]
        )
        let snapshot = makeSnapshot(
            [
                .init(
                    path: "Sources/App/Public.swift",
                    source: """
                    import struct ShadowKit.PublicHost

                    extension PublicHost {
                        @DIContainer
                        struct PublicContainer {
                            @Provide(.input) var value: Int
                        }
                    }
                    """,
                    targetID: appID
                ),
                .init(
                    path: "Sources/App/MatchingSPI.swift",
                    source: """
                    @_spi(GeneratedCode) import struct ShadowKit.SPIHost

                    extension SPIHost {
                        @DIContainer
                        struct MatchingSPIContainer {
                            @Provide(.input) var value: Int
                        }
                    }
                    """,
                    targetID: appID
                ),
                .init(
                    path: "Sources/App/MismatchedSPI.swift",
                    source: """
                    @_spi(OtherGroup) import struct ShadowKit.SPIHost

                    extension SPIHost {
                        @DIContainer
                        struct MismatchedSPIContainer {
                            @Provide(.input) var value: Int
                        }
                    }
                    """,
                    targetID: appID
                ),
                .init(
                    path: "Sources/ShadowKit/Hosts.swift",
                    source: """
                    public struct PublicHost {}
                    public struct SPIHost {}

                    public extension PublicHost {
                        struct Swift {}
                    }

                    @_spi(GeneratedCode) public extension SPIHost {
                        struct _Concurrency {}
                    }
                    """,
                    targetID: shadowID
                ),
            ],
            manifest: manifest
        )

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )
        let declarationMatrix = ContainerSemanticBuildValidator
            .validateDeclarationMatrix(snapshot: snapshot)

        #expect(report.issues.isEmpty)
        #expect(declarationMatrix.issues.count == 3)
        #expect(Set(declarationMatrix.issues.map(\.code)) == [
            "container.unverifiable-enclosing-context",
        ])
    }

    @Test("Sibling exported imports are visible module-wide")
    func siblingExportedImportsReachContainerFiles() {
        let appID = WorkspaceTargetID.swiftPM(
            packageIdentity: "root-package",
            moduleName: "App"
        )
        let shadowID = WorkspaceTargetID.swiftPM(
            packageIdentity: "shadow-package",
            moduleName: "ShadowKit"
        )
        let manifest = WorkspaceAnalysisManifest(
            rootPackageIdentity: "root-package",
            rootPackageDirectory: "/workspace",
            primaryTargetID: appID,
            targets: [
                makeTarget(
                    id: appID,
                    packageIdentity: "root-package",
                    moduleName: "App",
                    role: .primary,
                    dependencies: [shadowID]
                ),
                makeTarget(
                    id: shadowID,
                    packageIdentity: "shadow-package",
                    moduleName: "ShadowKit"
                ),
            ]
        )

        for exportedImport in [
            "@_exported import ShadowKit",
            "public import ShadowKit",
            "@testable @_exported import ShadowKit",
            "@_spi(GeneratedCode) @_exported import ShadowKit",
        ] {
            let snapshot = makeSnapshot(
                [
                    .init(
                        path: "Sources/App/Container.swift",
                        source: """
                        @DIContainer(mainActor: true)
                        struct AppContainer {
                            @Provide(.input) var value: Int
                        }
                        """,
                        targetID: appID
                    ),
                    .init(
                        path: "Sources/App/Exports.swift",
                        source: exportedImport,
                        targetID: appID
                    ),
                    .init(
                        path: "Sources/ShadowKit/Shadow.swift",
                        source: """
                        public struct Swift {}
                        struct _Concurrency {}
                        @_spi(GeneratedCode) public let InnoDI = 0
                        """,
                        targetID: shadowID
                    ),
                ],
                manifest: manifest
            )

            let report = GeneratedQualifierBuildValidator.validate(
                snapshot: snapshot
            )

            #expect(report.issues.count == 1, Comment(rawValue: exportedImport))
            #expect(
                report.issues.first?.metadata["qualifier"] == "Swift",
                Comment(rawValue: exportedImport)
            )
        }
    }

    @Test("Re-export chains carry client SPI but never testable visibility")
    func reexportVisibilityUsesOuterImportCapabilities() {
        let appID = WorkspaceTargetID.swiftPM(
            packageIdentity: "root-package",
            moduleName: "App"
        )
        let facadeID = WorkspaceTargetID.swiftPM(
            packageIdentity: "facade-package",
            moduleName: "FacadeKit"
        )
        let shadowID = WorkspaceTargetID.swiftPM(
            packageIdentity: "shadow-package",
            moduleName: "ShadowKit"
        )
        let manifest = WorkspaceAnalysisManifest(
            rootPackageIdentity: "root-package",
            rootPackageDirectory: "/workspace",
            primaryTargetID: appID,
            targets: [
                makeTarget(
                    id: appID,
                    packageIdentity: "root-package",
                    moduleName: "App",
                    role: .primary,
                    dependencies: [facadeID]
                ),
                makeTarget(
                    id: facadeID,
                    packageIdentity: "facade-package",
                    moduleName: "FacadeKit",
                    dependencies: [shadowID]
                ),
                makeTarget(
                    id: shadowID,
                    packageIdentity: "shadow-package",
                    moduleName: "ShadowKit"
                ),
            ]
        )
        let scenarios: [(
            appImport: String,
            facadeExport: String,
            expectedQualifiers: Set<String>
        )] = [
            (
                "@_spi(GeneratedCode) import FacadeKit",
                "@_exported import ShadowKit",
                ["InnoDI", "Swift"]
            ),
            (
                "import FacadeKit",
                "@_spi(GeneratedCode) @_exported import ShadowKit",
                ["InnoDI"]
            ),
            (
                "@testable import FacadeKit",
                "@testable @_exported import ShadowKit",
                ["InnoDI"]
            ),
        ]

        for scenario in scenarios {
            let snapshot = makeSnapshot(
                [
                    .init(
                        path: "Sources/App/Container.swift",
                        source: """
                        \(scenario.appImport)

                        @DIContainer(
                            validateDAG: false,
                            mainActor: true
                        )
                        struct AppContainer {
                            @Provide(factory: { missing in missing })
                            var value: Int
                        }
                        """,
                        targetID: appID
                    ),
                    .init(
                        path: "Sources/FacadeKit/Exports.swift",
                        source: scenario.facadeExport,
                        targetID: facadeID
                    ),
                    .init(
                        path: "Sources/ShadowKit/Shadows.swift",
                        source: """
                        @_spi(GeneratedCode) public struct Swift {}
                        public let InnoDI = 0
                        struct _Concurrency {}
                        """,
                        targetID: shadowID
                    ),
                ],
                manifest: manifest
            )

            let report = GeneratedQualifierBuildValidator.validate(
                snapshot: snapshot
            )
            let qualifiers = Set(
                report.issues.compactMap { $0.metadata["qualifier"] }
            )

            #expect(
                qualifiers == scenario.expectedQualifiers,
                Comment(
                    rawValue: "\(scenario.appImport) via \(scenario.facadeExport)"
                )
            )
        }
    }

    @Test("Setter-only access modifiers do not restrict getter visibility")
    func setterOnlyAccessModifiersRemainVisible() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Container.swift",
                source: """
                @DIContainer(validateDAG: false)
                struct AppContainer {
                    @Provide(factory: { missing in missing })
                    var value: Int
                }
                """
            ),
            .init(
                path: "Sources/App/State.swift",
                source: "private(set) var InnoDI = 0"
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.count == 1)
        #expect(report.issues.first?.metadata["qualifier"] == "InnoDI")
    }

    @Test("Resolved sync storage aliases do not require the InnoDI runtime qualifier")
    func storageAliasesDoNotCreateFallbackQualifierIssues() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Container.swift",
                source: """
                @DIContainer(validateDAG: false)
                struct AppContainer {
                    @Provide(.input) var value: Int

                    @Provide(factory: {
                        (_storage_value: Int) in _storage_value
                    })
                    var copy: Int

                    @Provide(
                        .shared,
                        Service.self,
                        with: [\\Self._storage_value]
                    )
                    var service: Service
                }

                let InnoDI = 0
                """
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.isEmpty)
    }

    @Test("Conditional managed members do not create qualifier issues")
    func conditionalManagedMembersDoNotCreateQualifierIssues() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Container.swift",
                source: """
                @DIContainer
                struct AppContainer {
                #if DEBUG
                    @Provide(asyncFactory: { () async -> Int in 1 })
                    var value: Int

                    @SubContainer(scope: .transient) var child: Child
                #endif
                }

                struct Swift {}
                struct _Concurrency {}
                let InnoDI = 0
                """
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.isEmpty)
    }

    @Test("Invalid managed members do not create phantom qualifier issues")
    func invalidManagedMembersDoNotCreateQualifierIssues() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Container.swift",
                source: """
                @DIContainer
                struct AppContainer {
                    @Provide(asyncFactory: { 1 })
                    var invalidAsync: Int

                    @SubContainer(
                        scope: .transient,
                        with: [\\.value],
                        bindings: [(child: \\.value, parent: \\.value)]
                    )
                    var invalidChild: Child
                }

                struct Swift {}
                enum _Concurrency {}
                let InnoDI = 0
                """
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.isEmpty)
    }

    @Test("Valid async peers keep qualifiers when a container sibling is invalid")
    func validAsyncPeerQualifiersSurviveInvalidSibling() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Container.swift",
                source: """
                @DIContainer
                struct AppContainer {
                    @Provide(asyncFactory: { () async -> Int in 1 })
                    var asyncValue: Int

                    @SubContainer(
                        scope: .transient,
                        with: [\\.value],
                        bindings: [(child: \\.value, parent: \\.value)]
                    )
                    var invalidChild: Child
                }

                struct Swift {}
                enum _Concurrency {}
                let InnoDI = 0
                """
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.count == 2)
        #expect(Set(report.issues.compactMap {
            $0.metadata["qualifier"]
        }) == ["Swift", "_Concurrency"])
    }

    @Test("Root-path loading catches cross-file shadows without a manifest")
    func rootPathValidationDoesNotReturnFalseGreen() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "InnoDI-Qualifier-Root-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try """
        @DIContainer(mainActor: true)
        struct AppContainer {
            @Provide(.input) var value: Int
        }
        """.write(
            to: rootURL.appendingPathComponent("Container.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "struct Swift {}\n".write(
            to: rootURL.appendingPathComponent("Shadow.swift"),
            atomically: true,
            encoding: .utf8
        )

        let report = try GeneratedQualifierBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(report.issues.count == 1)
        #expect(report.issues.first?.metadata["qualifier"] == "Swift")
    }

    @Test("Root-path fallback preserves imported external module prefixes")
    func rootPathExternalModuleExtensionIsNotSelfQualified() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Container.swift",
                source: """
                struct URL {
                    @DIContainer
                    struct Container {
                        @Provide(.input) var value: Int
                    }
                }
                """
            ),
            .init(
                path: "Sources/App/FoundationExtension.swift",
                source: """
                import Foundation

                extension Foundation.URL {
                    struct Swift {}
                }
                """
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.isEmpty)
    }

    @Test("Unsupported stacked container and bridge stay declaration-matrix owned")
    func unsupportedStackedAttributesDoNotCreateBridgeSite() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Unsupported.swift",
                source: """
                @DIContainer
                @DIEnvironmentBridge([])
                final class UnsupportedContainer {}
                """
            ),
        ])

        let qualifierReport = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )
        let declarationMatrix = ContainerSemanticBuildValidator
            .validateDeclarationMatrix(snapshot: snapshot)

        #expect(qualifierReport.issues.isEmpty)
        #expect(declarationMatrix.issues.count == 1)
        #expect(
            declarationMatrix.issues.first?.code
                == "container.unsupported-declaration-kind"
        )
    }

    @Test("File-scoped declarations do not leak across source files")
    func fileScopedShadowsRespectVisibility() {
        let snapshot = makeSnapshot([
            .init(
                path: "Sources/App/Container.swift",
                source: """
                @DIContainer
                struct AppContainer {
                    @Provide(.input) var value: Int
                }
                """
            ),
            .init(
                path: "Sources/App/PrivateShadow.swift",
                source: "private struct Swift {}"
            ),
        ])

        let report = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )

        #expect(report.issues.isEmpty)
    }
}

private struct QualifierSourceFixture {
    let path: String
    let source: String
    let targetID: WorkspaceTargetID?

    init(
        path: String,
        source: String,
        targetID: WorkspaceTargetID? = nil
    ) {
        self.path = path
        self.source = source
        self.targetID = targetID
    }
}

private func makeSnapshot(
    _ fixtures: [QualifierSourceFixture],
    manifest: WorkspaceAnalysisManifest? = nil
) -> WorkspaceSourceSnapshot {
    let rootURL = URL(fileURLWithPath: "/workspace")
    return WorkspaceSourceSnapshot(
        rootPath: rootURL.path,
        rootURL: rootURL,
        files: fixtures.map { fixture in
            WorkspaceSourceFile(
                relativePath: fixture.path,
                fileURL: rootURL.appendingPathComponent(fixture.path),
                syntax: Parser.parse(source: fixture.source),
                targetID: fixture.targetID,
                origin: fixture.targetID == nil ? nil : .declared
            )
        },
        primaryTargetID: manifest?.primaryTargetID,
        analysisManifest: manifest,
        analysisTargetIndex: manifest.map {
            WorkspaceAnalysisTargetIndex(targets: $0.targets)
        }
    )
}

private func makeTarget(
    id: WorkspaceTargetID,
    packageIdentity: String,
    moduleName: String,
    role: WorkspaceAnalysisTargetRole = .dependency,
    dependencies: [WorkspaceTargetID] = []
) -> WorkspaceAnalysisTarget {
    WorkspaceAnalysisTarget(
        id: id,
        packageIdentity: packageIdentity,
        packageDisplayName: packageIdentity,
        packageDirectory: "/workspace",
        targetName: moduleName,
        moduleName: moduleName,
        kind: .generic,
        role: role,
        sources: [],
        dependencies: dependencies.map { dependencyID in
            WorkspaceAnalysisDependency(
                kind: .target,
                name: dependencyID.rawValue,
                targetIDs: [dependencyID]
            )
        }
    )
}
