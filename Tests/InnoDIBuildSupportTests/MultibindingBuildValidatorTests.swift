import Foundation
import SwiftParser
import Testing

@testable import InnoDIBuildSupport
@testable import InnoDIWorkspaceAnalysis

@Suite("Multibinding build validation")
struct MultibindingBuildValidatorTests {
    @Test("valid ordered contributors satisfy the serialized contract")
    func validContributorsPass() throws {
        let report = try validate(
            """
            @DIContainer
            struct Container {
                @Provide(.shared, factory: Auth())
                var auth: any Interceptor

                @Provide(.transient, factory: Logging())
                var logging: any Interceptor

                @Multibinding([\\Self.auth, \\Self.logging])
                var interceptors: [any Interceptor]
            }
            """
        )
        #expect(report.issues.isEmpty)
    }

    @Test("invalid contributors emit stable build codes")
    func invalidContributorsFailClosed() throws {
        let report = try validate(
            """
            @DIContainer
            struct Container {
                @Provide(.shared, asyncFactory: { () async -> String in "remote" })
                var remote: String

                @Provide(.shared, factory: 42)
                var count: Int

                @Multibinding([
                    \\Self.remote,
                    \\Self.count,
                    \\Self.count,
                    \\Self.missing,
                ])
                var values: [String]
            }
            """
        )
        #expect(Set(report.issues.map(\.code)) == [
            "multibinding.async-contributor",
            "multibinding.type-mismatch",
            "multibinding.duplicate-contributor",
            "multibinding.unknown-contributor",
        ])
    }

    private func validate(_ source: String) throws -> ValidationIssueReport {
        let root = URL(fileURLWithPath: "/workspace")
        return try ContainerSemanticBuildValidator.validate(
            snapshot: WorkspaceSourceSnapshot(
                rootPath: root.path,
                rootURL: root,
                files: [
                    WorkspaceSourceFile(
                        relativePath: "Sources/App/Container.swift",
                        fileURL: root.appendingPathComponent(
                            "Sources/App/Container.swift"
                        ),
                        syntax: Parser.parse(source: source)
                    )
                ]
            )
        )
    }
}
