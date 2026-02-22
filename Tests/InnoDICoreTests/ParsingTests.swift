//
//  ParsingTests.swift
//  InnoDICoreTests
//

import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDICore

struct ParsingTests {
    @Test
    func parseDIContainerAttribute() {
        let source = """
        @DIContainer(validate: false, root: true)
        struct AppContainer {}
        """
        guard let decl = firstStructDecl(in: source) else {
            #expect(Bool(false), "Expected struct declaration.")
            return
        }

        let info = InnoDICore.parseDIContainerAttribute(decl.attributes)
        #expect(info?.validate == false)
        #expect(info?.root == true)
    }

    @Test
    func parseProvideAttributeSharedFactory() {
        let source = """
        struct AppContainer {
            @Provide(.shared, factory: Foo())
            var foo: Foo
        }
        """
        guard let decl = firstVarDecl(in: source) else {
            #expect(Bool(false), "Expected variable declaration.")
            return
        }

        let info = InnoDICore.parseProvideAttribute(decl.attributes)
        #expect(info != nil)
        #expect(info?.scope == .shared)
        #expect(info?.scopeName == "shared")
        #expect(info?.factoryExpr != nil)
    }

    @Test
    func parseProvideAttributeInput() {
        let source = """
        struct AppContainer {
            @Provide(.input)
            var bar: Bar
        }
        """
        guard let decl = firstVarDecl(in: source) else {
            #expect(Bool(false), "Expected variable declaration.")
            return
        }

        let info = InnoDICore.parseProvideAttribute(decl.attributes)
        #expect(info != nil)
        #expect(info?.scope == .input)
        #expect(info?.scopeName == "input")
        #expect(info?.factoryExpr == nil)
    }
    
    @Test
    func parseProvideAttributeTransient() {
        let source = """
        struct AppContainer {
            @Provide(.transient, factory: { ViewModel() })
            var viewModel: ViewModel
        }
        """
        guard let decl = firstVarDecl(in: source) else {
            #expect(Bool(false), "Expected variable declaration.")
            return
        }

        let info = InnoDICore.parseProvideAttribute(decl.attributes)
        #expect(info != nil)
        #expect(info?.scope == .transient)
        #expect(info?.scopeName == "transient")
        #expect(info?.factoryExpr != nil)
    }
    
    @Test
    func parseProvideAttributeConcrete() {
        let source = """
        struct AppContainer {
            @Provide(.shared, factory: URLSession.shared, concrete: true)
            var session: URLSession
        }
        """
        guard let decl = firstVarDecl(in: source) else {
            #expect(Bool(false), "Expected variable declaration.")
            return
        }

        let info = InnoDICore.parseProvideAttribute(decl.attributes)
        #expect(info != nil)
        #expect(info?.scope == .shared)
        #expect(info?.concrete == true)
    }
    
    @Test
    func parseProvideAttributeConcreteDefault() {
        let source = """
        struct AppContainer {
            @Provide(.shared, factory: SomeService())
            var service: SomeServiceProtocol
        }
        """
        guard let decl = firstVarDecl(in: source) else {
            #expect(Bool(false), "Expected variable declaration.")
            return
        }

        let info = InnoDICore.parseProvideAttribute(decl.attributes)
        #expect(info != nil)
        #expect(info?.concrete == false)
    }
}

private func firstStructDecl(in source: String) -> StructDeclSyntax? {
    let file = Parser.parse(source: source)
    return file.statements.compactMap { $0.item.as(StructDeclSyntax.self) }.first
}

private func firstVarDecl(in source: String) -> VariableDeclSyntax? {
    guard let structDecl = firstStructDecl(in: source) else { return nil }
    for member in structDecl.memberBlock.members {
        if let varDecl = member.decl.as(VariableDeclSyntax.self) {
            return varDecl
        }
    }
    return nil
}
