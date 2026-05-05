import Foundation
import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDIWorkspaceAnalysis

@Suite("DeferredWrapperAliasScan")
struct DeferredWrapperAliasScanTests {

    private func makeSnapshot(
        _ files: [(path: String, source: String)],
        rootPath: String = "/workspace"
    ) -> WorkspaceSourceSnapshot {
        let rootURL = URL(fileURLWithPath: rootPath)
        let workspaceFiles = files.map { entry -> WorkspaceSourceFile in
            let syntax = Parser.parse(source: entry.source)
            let url = rootURL.appendingPathComponent(entry.path)
            return WorkspaceSourceFile(
                relativePath: entry.path,
                fileURL: url,
                syntax: syntax
            )
        }
        return WorkspaceSourceSnapshot(
            rootPath: rootPath,
            rootURL: rootURL,
            files: workspaceFiles
        )
    }

    @Test("bare Lazy typealias is reported")
    func bareLazyAlias() {
        let snapshot = makeSnapshot([
            ("Sources/Module/A.swift", """
            typealias DeferredFoo = Lazy<Foo>
            """)
        ])

        let findings = scanDeferredWrapperAliases(in: snapshot)

        #expect(findings.count == 1)
        #expect(findings.first?.kind == .lazy)
        #expect(findings.first?.aliasName == "DeferredFoo")
        #expect(findings.first?.relativePath == "Sources/Module/A.swift")
    }

    @Test("qualified InnoDI.Provider typealias is reported")
    func qualifiedProviderAlias() {
        let snapshot = makeSnapshot([
            ("Sources/Module/B.swift", """
            typealias FreshBar = InnoDI.Provider<Bar>
            """)
        ])

        let findings = scanDeferredWrapperAliases(in: snapshot)

        #expect(findings.count == 1)
        #expect(findings.first?.kind == .provider)
        #expect(findings.first?.aliasName == "FreshBar")
    }

    @Test("typealias to an unrelated type is not reported")
    func unrelatedAlias() {
        let snapshot = makeSnapshot([
            ("Sources/Module/C.swift", """
            typealias Numbers = Array<Int>
            typealias Factory<T> = () -> T
            """)
        ])

        let findings = scanDeferredWrapperAliases(in: snapshot)

        #expect(findings.isEmpty)
    }

    @Test("multiple files contribute to the cross-file finding set")
    func crossFileFindings() {
        let snapshot = makeSnapshot([
            ("Sources/Module/D.swift", """
            typealias DeferredA = Lazy<A>
            """),
            ("Sources/Module/E.swift", """
            typealias DeferredB = InnoDI.Lazy<B>
            typealias FreshC = Provider<C>
            """)
        ])

        let findings = scanDeferredWrapperAliases(in: snapshot)
            .sorted { $0.aliasName < $1.aliasName }

        #expect(findings.count == 3)
        #expect(findings.map(\.aliasName) == ["DeferredA", "DeferredB", "FreshC"])
        #expect(findings.map(\.kind) == [.lazy, .lazy, .provider])
    }

    @Test("source location reflects the alias name position")
    func aliasLocation() {
        let snapshot = makeSnapshot([
            ("Sources/Module/F.swift", """

            // leading comment
            typealias DeferredFoo = Lazy<Foo>
            """)
        ])

        let findings = scanDeferredWrapperAliases(in: snapshot)

        #expect(findings.first?.line == 3)
        #expect(findings.first?.column == 11) // start column of `DeferredFoo`
    }
}
