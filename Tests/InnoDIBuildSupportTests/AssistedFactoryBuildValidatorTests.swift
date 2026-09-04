import Foundation
import SwiftParser
import Testing

@testable import InnoDIBuildSupport
@testable import InnoDIWorkspaceAnalysis

@Suite("Assisted factory build validation")
struct AssistedFactoryBuildValidatorTests {
    @Test("complete static bindings leave assisted inputs at call time")
    func validPartitionPasses() throws {
        let report = try ContainerSemanticBuildValidator.validate(
            snapshot: snapshot(parentBindings: """
            [
                (child: \\Child.repository, parent: \\Parent.repository),
            ]
            """)
        )
        #expect(report.issues.isEmpty)
    }

    @Test("invalid static and assisted bindings emit stable diagnostics")
    func invalidPartitionFailsClosed() throws {
        let report = try ContainerSemanticBuildValidator.validate(
            snapshot: snapshot(parentBindings: """
            [
                (child: \\Child.sessionID, parent: \\Parent.repository),
                (child: \\Child.sessionID, parent: \\Parent.repository),
                (child: \\Child.missing, parent: \\Parent.repository),
            ]
            """)
        )
        #expect(Set(report.issues.map(\.code)) == [
            "assisted-factory.assisted-input-bound-as-static",
            "assisted-factory.duplicate-static-binding",
            "assisted-factory.unknown-static-input",
            "assisted-factory.missing-static-binding",
        ])
    }

    private func snapshot(parentBindings: String) -> WorkspaceSourceSnapshot {
        let root = URL(fileURLWithPath: "/workspace")
        let sources = [
            (
                "Sources/App/Child.swift",
                """
                @DIContainer
                struct Child {
                    @Input var repository: Repository
                    @Input(.assisted) var sessionID: Int

                    @AssistedFactory(
                        Child.self,
                        static: [\\Child.repository],
                        assisted: [\\Child.sessionID]
                    )
                    struct AssistedFactory {}
                }
                """
            ),
            (
                "Sources/App/Parent.swift",
                """
                @DIContainer
                struct Parent {
                    @Input var repository: Repository

                    @SubContainerFactory(
                        Child.self,
                        bindings: \(parentBindings)
                    )
                    var child: Child.AssistedFactory
                }
                """
            ),
        ]
        return WorkspaceSourceSnapshot(
            rootPath: root.path,
            rootURL: root,
            files: sources.map { path, source in
                WorkspaceSourceFile(
                    relativePath: path,
                    fileURL: root.appendingPathComponent(path),
                    syntax: Parser.parse(source: source)
                )
            }
        )
    }
}
