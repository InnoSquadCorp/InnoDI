import Foundation
import SwiftParser
import Testing

@testable import InnoDIBuildSupport
@testable import InnoDIWorkspaceAnalysis

/// A plugin snapshot holds every target the build can see, including InnoDI's
/// own sources, so unqualified declaration paths repeat across targets. Before
/// the semantic validator scoped them, every unqualified `Lazy<T>` factory
/// parameter was reported against InnoDI's own `Lazy`, and a repeated path
/// trapped on a duplicate dictionary key.
@Suite("Container semantic validation target scope")
struct ContainerSemanticTargetScopeTests {
    private static let innoDI = WorkspaceTargetID.swiftPM(packageIdentity: "innodi", moduleName: "InnoDI")
    private static let app = WorkspaceTargetID.swiftPM(packageIdentity: "app", moduleName: "App")
    private static let feature = WorkspaceTargetID.swiftPM(packageIdentity: "app", moduleName: "Feature")

    private static let innoDIWrappers = """
        public struct Lazy<Value> {}
        public struct Provider<Value> {}
        """

    private static let deferredConsumer = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: { Token() })
            var token: Token

            @Provide(.transient, factory: { Token() })
            var freshToken: Token

            @Provide(.shared, factory: { (token: Lazy<Token>) in Client() })
            var client: Client

            @Provide(.shared, factory: { (freshToken: Provider<Token>) in Client() })
            var providerClient: Client
        }
        """

    @Test("InnoDI's own wrappers do not make a consumer qualify Lazy or Provider")
    func dependencyWrappersAreNotSameModule() throws {
        let report = try ContainerSemanticBuildValidator.validate(snapshot: snapshot([
            (Self.innoDI, "InnoDI/InnoDI.swift", Self.innoDIWrappers),
            (Self.app, "App/AppContainer.swift", Self.deferredConsumer),
        ]))
        #expect(report.issues.isEmpty)

        // Control: the same declarations in one module still shadow InnoDI.
        let sameModule = try ContainerSemanticBuildValidator.validate(snapshot: snapshot([
            (Self.app, "App/Wrappers.swift", Self.innoDIWrappers),
            (Self.app, "App/AppContainer.swift", Self.deferredConsumer),
        ]))
        #expect(sameModule.issues.map(\.code) == [
            "provide.deferred-wrapper-qualification-required",
            "provide.deferred-wrapper-qualification-required",
        ])
    }

    @Test("A consumer's own Lazy is reported without trapping on InnoDI's")
    func consumerWrapperNextToInnoDIWrapper() throws {
        let report = try ContainerSemanticBuildValidator.validate(snapshot: snapshot([
            (Self.innoDI, "InnoDI/InnoDI.swift", Self.innoDIWrappers),
            (Self.app, "App/Lazy.swift", "struct Lazy<Value> {}"),
            (Self.app, "App/AppContainer.swift", Self.deferredConsumer),
        ]))
        let issue = try #require(report.issues.first)
        #expect(report.issues.count == 1)
        #expect(issue.code == "provide.deferred-wrapper-qualification-required")
        #expect(issue.notes.map { $0.location?.filePath } == ["/workspace/App/Lazy.swift"])
    }

    @Test("Containers that share a name in two targets resolve to their own target")
    func repeatedContainerNamesStayPerTarget() throws {
        let parent = """
            @DIContainer
            struct AppContainer {
                @Input var appConfig: Config

                @SubContainer(
                    scope: .shared,
                    bindings: [(child: \\FeatureContainer.settings, parent: \\Self.appConfig)]
                )
                var feature: FeatureContainer
            }
            """
        let report = try ContainerSemanticBuildValidator.validate(snapshot: snapshot([
            (Self.feature, "Feature/FeatureContainer.swift", """
                @DIContainer
                struct FeatureContainer {
                    @Input var config: Config
                }

                @DIContainer
                struct AppContainer {
                    @Input var config: Config
                }
                """),
            (Self.app, "App/FeatureContainer.swift", """
                @DIContainer
                struct FeatureContainer {
                    @Input var settings: Config
                }
                """),
            (Self.app, "App/AppContainer.swift", parent),
        ]))
        // The app's own FeatureContainer declares `settings`; the feature
        // module's same-named container, which does not, is not consulted.
        #expect(report.issues.isEmpty)
    }

    @Test("A child container declared only in another target is still checked")
    func uniqueContainerInAnotherTargetIsChecked() throws {
        let report = try ContainerSemanticBuildValidator.validate(snapshot: snapshot([
            (Self.feature, "Feature/FeatureContainer.swift", """
                @DIContainer
                struct FeatureContainer {
                    @Input var config: Config
                }
                """),
            (Self.app, "App/AppContainer.swift", """
                @DIContainer
                struct AppContainer {
                    @Input var appConfig: Config

                    @SubContainer(
                        scope: .shared,
                        bindings: [(child: \\FeatureContainer.settings, parent: \\Self.appConfig)]
                    )
                    var feature: FeatureContainer
                }
                """),
        ]))
        #expect(report.issues.map(\.code) == ["sub.unknown-child-input"])
    }

    private func snapshot(
        _ sources: [(target: WorkspaceTargetID, path: String, source: String)]
    ) -> WorkspaceSourceSnapshot {
        let root = URL(fileURLWithPath: "/workspace")
        return WorkspaceSourceSnapshot(
            rootPath: root.path,
            rootURL: root,
            files: sources.map { target, path, source in
                WorkspaceSourceFile(
                    relativePath: path,
                    fileURL: root.appendingPathComponent(path),
                    syntax: Parser.parse(source: source),
                    targetID: target,
                    origin: .declared
                )
            }
        )
    }
}
