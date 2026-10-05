import Foundation
import InnoDIWorkspaceAnalysis
import SwiftParser
import Testing

@testable import InnoDIDependencyGraphCore

@Suite("Conditional container identity diagnostics")
struct ConditionalIdentityDiagnosticTests {
    @Test("Mutually exclusive declarations require compiler conditions without merging graphs")
    func mutuallyExclusiveDeclarationsHaveAnHonestPreflightFailure() throws {
        let source = """
        #if FAST_BUILD
        @DIContainer(validateDAG: false) struct App {
            @Provide(.shared, factory: 1) var first: Int
        }
        #else
        @DIContainer struct App {
            @Provide(.shared, factory: 2) var second: Int
        }
        #endif
        """
        for targetScoped in [false, true] {
            let snapshot = snapshot(sources: ["Sources/App.swift": source], targetScoped: targetScoped)
            let validation = validateDependencyGraph(snapshot: snapshot)
            let graph = collectDependencyGraph(snapshot: snapshot, validateDAG: true)
            let render = collectRenderableDependencyGraph(
                snapshot: snapshot, validateDAG: false, rootPruning: .all
            )

            #expect(validation.exitCode == 3)
            #expect(validation.stderr.contains("[graph.conditional-identity-unresolved]"))
            #expect(!validation.stderr.contains("[graph.duplicate-semantic-identity]"))
            #expect(validation.stderr.contains("Sources/App.swift:2:1"))
            #expect(validation.stderr.contains("Sources/App.swift:6:1"))
            #expect(validation.stderr.contains("compiler conditions"))
            #expect(graph.preflightFailure?.exitCode == 3)
            #expect(graph.nodes.isEmpty)
            #expect(graph.edges.isEmpty)
            #expect(graph.providers.isEmpty)
            #expect(render.preflightFailure?.exitCode == 3)
            #expect(render.nodes.isEmpty)
        }
    }

    @Test("Separate conditional blocks do not imply an active compiler configuration")
    func independentConditionsAreNotAssumedToOverlapOrBeExclusive() {
        let snapshot = snapshot(sources: ["Sources/App.swift": """
        #if FEATURE_A
        @DIContainer struct App {}
        #endif
        #if FEATURE_B
        @DIContainer struct App {}
        #endif
        """])

        let result = validateDependencyGraph(snapshot: snapshot)
        #expect(result.exitCode == 3)
        #expect(result.stderr.contains("[graph.conditional-identity-unresolved]"))
        #expect(!result.stderr.contains("[graph.duplicate-semantic-identity]"))
        #expect(result.stderr.contains("Sources/App.swift:2:1"))
        #expect(result.stderr.contains("Sources/App.swift:5:1"))
    }

    @Test("Conditional declarations do not hide an already-proven unconditional duplicate")
    func definiteDuplicatesTakePrecedence() {
        let snapshot = snapshot(sources: ["Sources/App.swift": """
        @DIContainer struct App {}
        @DIContainer struct App {}
        #if FEATURE
        @DIContainer struct App {}
        #endif
        """])
        let result = validateDependencyGraph(snapshot: snapshot)
        #expect(result.exitCode == 3)
        #expect(result.stderr.contains("[graph.duplicate-semantic-identity]"))
        #expect(!result.stderr.contains("[graph.conditional-identity-unresolved]"))
        for line in [1, 2, 4] {
            #expect(result.stderr.contains("Sources/App.swift:\(line):1"))
        }
    }

    @Test("Unconditional duplicate identities retain every declaration location")
    func ordinaryDuplicatesRemainErrorsWithPreciseLocations() {
        let snapshot = snapshot(sources: [
            "Sources/A.swift": """
            @DIContainer struct App {}

              @DIContainer struct App {}
            """,
            "Sources/B.swift": "\n@DIContainer struct App {}\n",
        ])

        let result = validateDependencyGraph(snapshot: snapshot)
        #expect(result.exitCode == 3)
        #expect(result.stderr.contains("[graph.duplicate-semantic-identity]"))
        #expect(!result.stderr.contains("[graph.conditional-identity-unresolved]"))
        #expect(result.stderr.contains("declarations: 3"))
        #expect(result.stderr.contains("Sources/A.swift:1:1"))
        #expect(result.stderr.contains("Sources/A.swift:3:3"))
        #expect(result.stderr.contains("Sources/B.swift:2:1"))
    }

    @Test("A container nested inside a conditional namespace keeps its conditional context")
    func enclosingConditionalDeclarationsAreRecognized() {
        let snapshot = snapshot(sources: ["Sources/App.swift": """
        #if FEATURE
        enum Namespace {
            @DIContainer struct App {}
        }
        #else
        enum Namespace {
            @DIContainer struct App {}
        }
        #endif
        """])

        let result = validateDependencyGraph(snapshot: snapshot)
        #expect(result.stderr.contains("[graph.conditional-identity-unresolved]"))
        #expect(result.stderr.contains("::Namespace.App"))
        #expect(result.stderr.contains("Sources/App.swift:3:5"))
        #expect(result.stderr.contains("Sources/App.swift:7:5"))
    }

    @Test("One declaration with conditional factory implementation remains supported")
    func conditionalImplementationDoesNotCreateAnIdentityCollision() {
        let snapshot = snapshot(sources: ["Sources/App.swift": """
        @DIContainer struct App {
            @Provide(.shared, factory: {
                #if FEATURE
                return 1
                #else
                return 2
                #endif
            }) var value: Int
        }
        """])

        let result = validateDependencyGraph(snapshot: snapshot)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(collectDependencyGraph(snapshot: snapshot, validateDAG: true).nodes.count == 1)
    }

    private func snapshot(
        sources: [String: String],
        targetScoped: Bool = true
    ) -> WorkspaceSourceSnapshot {
        let root = URL(fileURLWithPath: "/workspace/conditional-identity-fixture")
        let targetID = WorkspaceTargetID.swiftPM(packageIdentity: "fixture", moduleName: "App")
        let files = sources.sorted { $0.key < $1.key }.map { path, source in
            WorkspaceSourceFile(
                relativePath: path,
                fileURL: root.appendingPathComponent(path),
                syntax: Parser.parse(source: source),
                targetID: targetScoped ? targetID : nil,
                origin: targetScoped ? .declared : nil
            )
        }
        let manifest = WorkspaceAnalysisManifest(
            rootPackageIdentity: "fixture",
            rootPackageDirectory: root.path,
            primaryTargetID: targetID,
            targets: [WorkspaceAnalysisTarget(
                id: targetID,
                packageIdentity: "fixture",
                packageDisplayName: "Fixture",
                packageDirectory: root.path,
                targetName: "App",
                moduleName: "App",
                kind: .generic,
                role: .primary,
                sources: files.map {
                    WorkspaceAnalysisSource(
                        filePath: $0.filePath,
                        logicalPath: $0.relativePath,
                        origin: .declared
                    )
                },
                dependencies: []
            )]
        )
        return WorkspaceSourceSnapshot(
            rootPath: root.path,
            rootURL: root,
            files: files,
            primaryTargetID: targetScoped ? targetID : nil,
            analysisManifest: targetScoped ? manifest : nil
        )
    }
}
