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
        @DIContainer(root: true, validateDAG: false, mainActor: true)
        struct AppContainer {}
        """
        guard let decl = firstStructDecl(in: source) else {
            #expect(Bool(false), "Expected struct declaration.")
            return
        }

        let info = InnoDICore.parseDIContainerAttribute(decl.attributes)
        #expect(info?.root == true)
        #expect(info?.validateDAG == false)
        #expect(info?.mainActor == true)
    }

    @Test
    func parseDIContainerAttributeDefaultsValidateDAGToTrue() {
        let source = """
        @DIContainer
        struct AppContainer {}
        """
        guard let decl = firstStructDecl(in: source) else {
            #expect(Bool(false), "Expected struct declaration.")
            return
        }

        let info = InnoDICore.parseDIContainerAttribute(decl.attributes)
        #expect(info?.root == false)
        #expect(info?.validateDAG == true)
        #expect(info?.mainActor == false)
    }

    @Test
    func parseDIContainerAttributePreservesInvalidBoolArguments() throws {
        let source = """
        @DIContainer(root: isRoot, validateDAG: !FAST_BUILD, mainActor: Flags.mainActor)
        struct AppContainer {}
        """
        let decl = try #require(firstStructDecl(in: source))

        let parsed = InnoDICore.parseDIContainerAttribute(decl.attributes)
        let info = try #require(parsed)
        #expect(info.root == false)
        #expect(info.validateDAG == true)
        #expect(info.mainActor == false)
        #expect(info.rootParseState == .invalid)
        #expect(info.validateDAGParseState == .invalid)
        #expect(info.mainActorParseState == .invalid)
    }

    @Test
    func parseProvideAttributeSharedFactory() throws {
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

        let parsed = InnoDICore.parseProvideAttribute(decl.attributes)
        let info = try #require(parsed)
        #expect(info.scope == .shared)
        #expect(info.scopeName == "shared")
        #expect(info.factoryExpr != nil)
    }

    @Test
    func parseProvideAttributeInput() throws {
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

        let parsed = InnoDICore.parseProvideAttribute(decl.attributes)
        let info = try #require(parsed)
        #expect(info.scope == .input)
        #expect(info.scopeName == "input")
        #expect(info.factoryExpr == nil)
    }
    
    @Test
    func parseProvideAttributeTransient() throws {
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

        let parsed = InnoDICore.parseProvideAttribute(decl.attributes)
        let info = try #require(parsed)
        #expect(info.scope == .transient)
        #expect(info.scopeName == "transient")
        #expect(info.factoryExpr != nil)
    }

    @Test
    func parseProvideAttributeAsyncFactory() throws {
        let source = """
        struct AppContainer {
            @Provide(.transient, asyncFactory: { () async throws in try await ViewModel.load() })
            var viewModel: ViewModel
        }
        """
        guard let decl = firstVarDecl(in: source) else {
            #expect(Bool(false), "Expected variable declaration.")
            return
        }

        let parsed = InnoDICore.parseProvideAttribute(decl.attributes)
        let info = try #require(parsed)
        #expect(info.scope == .transient)
        #expect(info.asyncFactoryExpr != nil)
        #expect(info.asyncFactoryIsThrowing == true)
    }
    
    @Test
    func parseProvideAttributeConcrete() throws {
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

        let parsed = InnoDICore.parseProvideAttribute(decl.attributes)
        let info = try #require(parsed)
        #expect(info.scope == .shared)
        #expect(info.concrete == true)
    }
    
    @Test
    func parseProvideAttributeConcreteDefault() throws {
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

        let parsed = InnoDICore.parseProvideAttribute(decl.attributes)
        let info = try #require(parsed)
        #expect(info.concrete == false)
    }

    @Test
    func parseProvideAttributePreservesInvalidConcreteBool() throws {
        let source = """
        struct AppContainer {
            @Provide(.shared, factory: SomeService(), concrete: shouldUseConcrete)
            var service: SomeService
        }
        """
        let decl = try #require(firstVarDecl(in: source))

        let parsed = InnoDICore.parseProvideAttribute(decl.attributes)
        let info = try #require(parsed)
        #expect(info.concrete == false)
        #expect(info.concreteParseState == .invalid)
    }

    @Test
    func parseProvideAttributePreservesInvalidWithArgument() throws {
        let source = """
        struct AppContainer {
            @Provide(.shared, SomeService.self, with: dependencies)
            var service: SomeServiceProtocol
        }
        """
        let decl = try #require(firstVarDecl(in: source))

        let parsed = InnoDICore.parseProvideAttribute(decl.attributes)
        let info = try #require(parsed)
        #expect(info.dependencies.isEmpty)
        #expect(info.dependenciesParseState == .invalid)
    }

    @Test
    func parseSubContainerAttributePreservesMalformedBindings() throws {
        let source = """
        struct AppContainer {
            @SubContainer(scope: .shared, bindings: [(child: \\.featureConfig)])
            var feature: FeatureContainer
        }
        """
        let decl = try #require(firstVarDecl(in: source))

        let parsed = InnoDICore.parseSubContainerAttribute(decl.attributes)
        let info = try #require(parsed)
        #expect(info.bindings.isEmpty)
        #expect(info.bindingsParseState == .invalid)
    }

    @Test
    func findAttributeAcceptsAllowedQualifiedModuleNames() throws {
        let source = """
        struct ParentContainer {
            @InnoDISwiftUI.DIFeatureRoot(DashboardRootView.self)
            var dashboard: DashboardContainer
        }
        """
        let decl = try #require(firstVarDecl(in: source))
        let attribute = findAttribute(
            named: "DIFeatureRoot",
            allowingQualifiedModules: ["InnoDISwiftUI"],
            in: decl.attributes
        )
        #expect(attribute != nil)
    }

    @Test
    func findAttributeRejectsForeignQualifiedModuleNames() throws {
        let source = """
        struct ParentContainer {
            @OtherDI.DIFeatureRoot(DashboardRootView.self)
            var dashboard: DashboardContainer
        }
        """
        let decl = try #require(firstVarDecl(in: source))
        let attribute = findAttribute(
            named: "DIFeatureRoot",
            allowingQualifiedModules: ["InnoDISwiftUI"],
            in: decl.attributes
        )
        #expect(attribute == nil)
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
