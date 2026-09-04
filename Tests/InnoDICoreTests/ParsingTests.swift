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
    func managedMemberSemanticsOwnRoleMatchingAndArgumentParsing() throws {
        let provide = try #require(
            firstVarDecl(
                in: "struct C { @InnoDI.Provide(.input) var service: Service }"
            )
        )
        let provideSemantics = parseManagedMemberSemantics(provide.attributes)

        #expect(provideSemantics.hasAnyRole)
        #expect(provideSemantics.hasExactlyOneRole)
        #expect(!provideSemantics.hasConflictingRoles)
        switch provideSemantics.uniqueRole {
        case .provide(_, let arguments):
            #expect(arguments.scope == .input)
        default:
            Issue.record("Expected one parsed @Provide role")
        }

        let subContainer = try #require(
            firstVarDecl(
                in: "struct C { @SubContainer(scope: .transient) var child: ChildContainer }"
            )
        )
        let subContainerSemantics = parseManagedMemberSemantics(
            subContainer.attributes
        )
        switch subContainerSemantics.uniqueRole {
        case .subContainer(_, let arguments):
            #expect(arguments.scope == .transient)
        default:
            Issue.record("Expected one parsed @SubContainer role")
        }
    }

    @Test
    func inputAndContainerRoleSyntaxNormalizeIntoCoreIR() throws {
        let input = try #require(
            firstVarDecl(
                in: "struct C { @InnoDI.Input(.assisted, escaping: true) var callback: Callback }"
            )
        )
        let semantics = parseManagedMemberSemantics(input.attributes)
        let arguments = try #require(semantics.provideArguments)
        #expect(arguments.scope == .input)
        #expect(arguments.inputKind == .assisted)
        #expect(arguments.escaping)

        let container = try #require(
            firstStructDecl(
                in: "@DIContainerRole(.root, isolation: .mainActor) struct C {}"
            )
        )
        let parsedOptions = InnoDICore.parseDIContainerAttribute(
            container.attributes
        )
        let options = try #require(parsedOptions)
        #expect(options.role == .root)
        #expect(options.root)
        #expect(options.isolation == .mainActor)
        #expect(options.mainActor)
    }

    @Test
    func managedMemberSemanticsFailClosedForDuplicatesAndConflicts() throws {
        let conflicting = try #require(
            firstVarDecl(
                in: "struct C { @Provide(.input) @SubContainer(scope: .shared) var child: Child }"
            )
        )
        let conflict = parseManagedMemberSemantics(conflicting.attributes)
        #expect(conflict.hasAnyRole)
        #expect(conflict.hasConflictingRoles)
        #expect(!conflict.hasExactlyOneRole)

        let duplicate = try #require(
            firstVarDecl(
                in: "struct C { @Provide(.input) @InnoDI.Provide(.input) var value: Value }"
            )
        )
        let duplicates = parseManagedMemberSemantics(duplicate.attributes)
        #expect(duplicates.provideAttributes.count == 2)
        #expect(!duplicates.hasConflictingRoles)
        #expect(!duplicates.hasExactlyOneRole)

        let mixedInputSpelling = try #require(
            firstVarDecl(
                in: "struct C { @Input @Provide(.input) var value: Value }"
            )
        )
        #expect(
            parseManagedMemberSemantics(mixedInputSpelling.attributes)
                .provideAttributes.count == 2
        )

        let lookalike = try #require(
            firstVarDecl(
                in: "struct C { @Other.Provide(.input) var ignored: Value }"
            )
        )
        #expect(!parseManagedMemberSemantics(lookalike.attributes).hasAnyRole)
    }

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
    func parseProvideAttributePreservesUnknownExplicitScope() throws {
        let source = """
        struct AppContainer {
            @Provide(.request, factory: Service())
            var service: Service
        }
        """
        let decl = try #require(firstVarDecl(in: source))

        let parsed = InnoDICore.parseProvideAttribute(decl.attributes)
        let info = try #require(parsed)
        #expect(info.scope == nil)
        #expect(info.scopeName == "request")
        #expect(info.scopeExpr?.trimmedDescription == ".request")
    }

    @Test
    func parseProvideAttributePreservesDynamicExplicitScope() throws {
        let source = """
        struct AppContainer {
            @Provide(useTransient ? .transient : .shared, factory: Service())
            var service: Service
        }
        """
        let decl = try #require(firstVarDecl(in: source))

        let parsed = InnoDICore.parseProvideAttribute(decl.attributes)
        let info = try #require(parsed)
        #expect(info.scope == nil)
        #expect(info.scopeName == "useTransient ? .transient : .shared")
        #expect(info.scopeExpr?.trimmedDescription == "useTransient ? .transient : .shared")
    }

    @Test
    func parseProvideAttributeRejectsLookalikeQualifiedScope() throws {
        let source = """
        struct AppContainer {
            @Provide(ScopeChooser.shared, factory: Service())
            var service: Service
        }
        """
        let decl = try #require(firstVarDecl(in: source))

        let parsed = InnoDICore.parseProvideAttribute(decl.attributes)
        let info = try #require(parsed)
        #expect(info.scope == nil)
        #expect(info.scopeName == "ScopeChooser.shared")
        #expect(info.scopeExpr?.trimmedDescription == "ScopeChooser.shared")
    }

    @Test
    func parseProvideAttributeAcceptsQualifiedDIScopeLiteral() throws {
        for spelling in ["DIScope.shared", "InnoDI.DIScope.shared"] {
            let source = """
            struct AppContainer {
                @Provide(\(spelling), factory: Service())
                var service: Service
            }
            """
            let decl = try #require(firstVarDecl(in: source))

            let parsed = InnoDICore.parseProvideAttribute(decl.attributes)
            let info = try #require(parsed)
            #expect(info.scope == .shared)
            #expect(info.scopeName == "shared")
            #expect(info.scopeExpr?.trimmedDescription == spelling)
        }
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
    func parseSubContainerAttributeRejectsStrictBindingTupleViolations() throws {
        let bindingSources = [
            "(child: \\.featureConfig, parent: \\.config, extra: \\.other)",
            "(\\.featureConfig, parent: \\.config)",
            "(child: \\.featureConfig, child: \\.fallbackConfig)",
            "(child: \\.featureConfig, parent: \\.config, parent: \\.fallbackConfig)",
            "(source: \\.featureConfig, parent: \\.config)",
        ]

        for bindingSource in bindingSources {
            let source = """
            struct AppContainer {
                @SubContainer(scope: .shared, bindings: [\(bindingSource)])
                var feature: FeatureContainer
            }
            """
            let decl = try #require(firstVarDecl(in: source))

            let parsed = InnoDICore.parseSubContainerAttribute(decl.attributes)
            let info = try #require(parsed)
            #expect(info.bindings.isEmpty)
            #expect(info.bindingsParseState == .invalid)
        }
    }

    @Test
    func parseSubContainerAttributeAcceptsReversedStrictBindingTuple() throws {
        let source = """
        struct AppContainer {
            @SubContainer(scope: .shared, bindings: [(parent: \\.config, child: \\.featureConfig)])
            var feature: FeatureContainer
        }
        """
        let decl = try #require(firstVarDecl(in: source))

        let parsed = InnoDICore.parseSubContainerAttribute(decl.attributes)
        let info = try #require(parsed)
        #expect(info.bindings == [
            SubContainerBindingArgument(childName: "featureConfig", parentName: "config")
        ])
    }

    @Test
    func findAttributeAcceptsAllowedQualifiedModuleNames() throws {
        let source = """
        struct ParentContainer {
            @InnoDISwiftUI.DIEnvironmentBridge([])
            var dashboard: DashboardContainer
        }
        """
        let decl = try #require(firstVarDecl(in: source))
        let attribute = findAttribute(
            named: "DIEnvironmentBridge",
            allowingQualifiedModules: ["InnoDISwiftUI"],
            in: decl.attributes
        )
        #expect(attribute != nil)
    }

    @Test
    func findAttributeRejectsForeignQualifiedModuleNames() throws {
        let source = """
        struct ParentContainer {
            @OtherDI.DIEnvironmentBridge([])
            var dashboard: DashboardContainer
        }
        """
        let decl = try #require(firstVarDecl(in: source))
        let attribute = findAttribute(
            named: "DIEnvironmentBridge",
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
