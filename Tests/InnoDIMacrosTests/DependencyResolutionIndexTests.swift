import InnoDICore
import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDIMacros

@Suite("Macro dependency availability index")
struct DependencyResolutionIndexTests {
    @Test("Parsed members preserve injectable versus ownership edges")
    func preservesEdgeBoundaries() throws {
        let source = Parser.parse(source: """
            @DIContainer struct Container {
                @Provide(.shared, asyncFactory: { (future: Int) async in future }) var asyncValue: Int
                @Provide(.shared, factory: { (future: Int, absent: Int) in future }) var first: Int
                @Provide(.shared, factory: 1) var future: Int
                @Input var input: Int
                @Provide(.transient, factory: { (asyncValue: Int, first: Int) in first }) var transient: Int
            }
            """)
        let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        let model = try #require(DIContainerParser.parse(
            declaration: declaration, context: TestMacroExpansionContext()
        ))
        let resolver = DependencyResolutionContext(members: model.members)
        #expect(resolver.status(of: "future", forMemberAt: 0) == .available)
        #expect(resolver.status(of: "future", forMemberAt: 1) == .unavailable)
        #expect(resolver.status(of: "absent", forMemberAt: 1) == .unknown)
        #expect(resolver.graphDependencies(forMemberAt: 0) == ["future"])
        #expect(resolver.graphDependencies(forMemberAt: 1).isEmpty)
        #expect(resolver.cycleDependencies(forMemberAt: 1) == ["future"])
        #expect(resolver.graphDependencies(forMemberAt: 4) == ["asyncValue", "first"])
        #expect(resolver.cycleDependencies(forMemberAt: -1).isEmpty)
        #expect(resolver.graphDependencies(forMemberAt: model.members.count).isEmpty)
    }

    @Test("Unmanaged declarations and child containers do not offset provider positions")
    func compactModelIndex() throws {
        let source = Parser.parse(source: """
            @DIContainer struct Container {
                static let constant = 1
                @Provide(.shared, factory: 1) var first: Int
                func unrelated() {}
                @SubContainer(scope: .shared, with: []) var child: Child
                @Provide(.shared, factory: { (first: Int) in first }) var second: Int
            }
            """)
        let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        let model = try #require(DIContainerParser.parse(
            declaration: declaration, context: TestMacroExpansionContext()
        ))
        #expect(model.members.map(\.name) == ["first", "second"])
        #expect(model.members[1].sourceOrder != 1)
        let resolver = DependencyResolutionContext(members: model.members)
        #expect(resolver.status(of: "first", forMemberAt: 1) == .available)
        #expect(resolver.status(of: "second", forMemberAt: 0) == .unavailable)
    }

    @Test("Deferred forward edges remain ownership edges")
    func deferredOwnershipIsNotAvailability() throws {
        let source = Parser.parse(source: """
            @DIContainer struct Container {
                @Provide(.shared, factory: { (later: Lazy<Int>) in later }) var first: Lazy<Int>
                @Provide(.shared, factory: 1) var later: Int
            }
            """)
        let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        let model = try #require(DIContainerParser.parse(
            declaration: declaration, context: TestMacroExpansionContext()
        ))
        let resolver = DependencyResolutionContext(members: model.members)
        #expect(resolver.graphDependencies(forMemberAt: 0).isEmpty)
        #expect(resolver.cycleDependencies(forMemberAt: 0) == ["later"])
    }
}
