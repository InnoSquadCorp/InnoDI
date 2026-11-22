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

    // The macro classifies a factory parameter only when its written type is
    // `Lazy<T>` / `Provider<T>` (bare or qualified). Any alias visible at a
    // factory parameter that names the wrapper defeats that detection.
    @Test("every alias that can stand in for a wrapper at a factory parameter is listed")
    func aliasesThatDefeatDetectionAreListed() {
        let snapshot = makeSnapshot([
            ("Sources/Module/Aliases.swift", """
            import InnoDI
            typealias TopLazy = Lazy<Int>
            typealias GenericLazy<T> = Lazy<T>
            typealias Qualified = InnoDI.Provider<Int>
            typealias Unbound = Lazy
            typealias Paren = (Lazy<Int>)
            typealias Chain = TopLazy
            typealias Unrelated = Vendor.Provider
            typealias OptionalLazy = Lazy<Int>?
            struct Vendor { struct Provider {} ; typealias NestedLazy = Lazy<Int> }
            func f() { typealias LocalLazy = Lazy<Int> }
            """)
        ])

        let findings = scanDeferredWrapperAliases(in: snapshot)

        #expect(findings.map(\.aliasName) == [
            "TopLazy", "GenericLazy", "Qualified", "Unbound", "Paren", "Chain", "NestedLazy",
        ])
        #expect(findings.map(\.kind) == [.lazy, .lazy, .provider, .lazy, .lazy, .lazy, .lazy])
    }

    @Test("a qualified wrapper name counts only under InnoDI or a module that re-exports it")
    func qualifiedWrapperRequiresInnoDIModule() {
        let snapshot = makeSnapshot([
            ("Sources/Module/A.swift", """
            typealias A = InnoDISwiftUI.Lazy<Int>
            typealias B = InnoDITesting.Provider<Int>
            typealias C = Vendor.Provider<Int>
            typealias D = Vendor.Lazy
            struct Vendor { struct Provider<T> {} ; struct Lazy {} }
            """)
        ])

        let findings = scanDeferredWrapperAliases(in: snapshot)

        #expect(findings.map(\.aliasName) == ["A", "B"])
        #expect(findings.map(\.kind) == [.lazy, .provider])
    }

    @Test("alias chains are followed across files, in any order, through type scopes")
    func aliasChainsAcrossFilesAndScopes() {
        let snapshot = makeSnapshot([
            ("Sources/Module/A.swift", """
            typealias Second = First
            typealias Qualified = Holder.Inner
            struct Box<T> { typealias Item = Lazy<T> }
            typealias Boxed = Box<Int>.Item
            """),
            ("Sources/Module/B.swift", """
            typealias First = (InnoDI.Provider<Int>)
            struct Holder { typealias Inner = First }
            extension Holder { typealias Scoped = Inner }
            """)
        ])

        let findings = scanDeferredWrapperAliases(in: snapshot)

        #expect(findings.map(\.aliasName) == [
            "Second", "Qualified", "Item", "Boxed", "First", "Inner", "Scoped",
        ])
        #expect(findings.map(\.kind) == [
            .provider, .provider, .lazy, .lazy, .provider, .provider, .provider,
        ])
    }

    @Test("an inner declaration of the referenced name shadows an outer wrapper alias")
    func innerDeclarationsShadowOuterAliases() {
        let snapshot = makeSnapshot([
            ("Sources/Module/A.swift", """
            typealias Deferred = Lazy<Int>
            struct Outer {
                struct Deferred {}
                typealias UsesNominal = Deferred
            }
            struct Other {
                typealias Deferred = Int
                typealias UsesAlias = Deferred
            }
            struct Plain {
                typealias UsesOuter = Deferred
            }
            """)
        ])

        let findings = scanDeferredWrapperAliases(in: snapshot)

        #expect(findings.map(\.aliasName) == ["Deferred", "UsesOuter"])
    }

    @Test("aliases local to functions, closures, and accessors are not listed")
    func localAliasesAreIgnored() {
        let snapshot = makeSnapshot([
            ("Sources/Module/A.swift", """
            struct Host {
                init() { typealias InInit = Lazy<Int> }
                func run() {
                    struct Local { typealias InLocalType = Lazy<Int> }
                    _ = { typealias InClosure = Lazy<Int> }
                }
                var computed: Int { typealias InGetter = Lazy<Int>; return 0 }
                var observed: Int = 0 { didSet { typealias InObserver = Lazy<Int> } }
                typealias Member = Provider<Int>
            }
            """)
        ])

        let findings = scanDeferredWrapperAliases(in: snapshot)

        #expect(findings.map(\.aliasName) == ["Member"])
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
