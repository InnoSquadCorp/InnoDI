import Foundation
import InnoDICore
import InnoDITestSupport
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("Opt-in dependency initialization order")
struct DependencyInitializationOrderTests {
    private static let policy = "initializationOrder: ContainerInitializationOrder.dependency"
    private static var macros: [String: any Macro.Type] {
        var result = DIContainerMacroTests.macros
        result["DIContainerRole"] = DIContainerRoleMacro.self
        result["InnoDI.DIContainerRole"] = DIContainerRoleMacro.self
        return result
    }

    @Test("Explicit declaration policy exactly matches omitted expansion")
    func preservesDefaultExpansion() {
        let members = """
            @Input var input: Int
            @Provide(.shared, factory: { (input: Int) in input }) var first: Int
            @Provide(.shared, initialization: .onDemand, factory: { (first: Int) in first }) var second: Int
            @Provide(.shared, asyncFactory: { (second: Int) async in second }) var third: Int
            @Provide(.transient, factory: { (first: Int) in first }) var fourth: Int
            """
        let omitted = expandMacroSource("@DIContainer struct Container { \(members) }", macros: Self.macros)
        let explicit = expandMacroSource("@DIContainer(initializationOrder: ContainerInitializationOrder.declaration) struct Container { \(members) }", macros: Self.macros)
        #expect(omitted.diagnostics.isEmpty)
        #expect(explicit.diagnostics.isEmpty)
        #expect(omitted.expansion == explicit.expansion)
    }

    @Test("Forward closure and Type.self with edges order only construction")
    func synchronousForwardEdges() throws {
        let members = """
            @Provide(.shared, Service.self, with: [\\Self.value]) var service: Service
            @Provide(.shared, factory: { (seed: Int) in seed + 1 }) var value: Int
            @Input var input: Int
            @Provide(.shared, factory: { (input: Int) in input }) var seed: Int
            """
        let (model, declaration) = try parse(members)
        try validate(model, declaration)
        let originalNames = model.members.map(\.name)
        let originalSourceOrder = model.members.map(\.sourceOrder)
        let plan = try DIContainerInitializationPlan(model: model)
        #expect(plan.syncShared.map(\.name) == ["seed", "value", "service"])
        #expect(plan.asyncShared.isEmpty)
        let generated = try DIContainerCodeGenerator.generateInit(for: model).description
        try expectBefore("self._storage_seed =", "self._storage_value =", in: generated)
        try expectBefore("self._storage_value =", "self._storage_service =", in: generated)
        let initializer = try #require(try DIContainerCodeGenerator.generateInit(for: model).as(InitializerDeclSyntax.self))
        #expect(initializer.signature.parameterClause.parameters.map { $0.firstName.text }
            == ["input", "service", "value", "seed", "_innoDITrace"])
        #expect(model.members.map(\.name) == originalNames)
        #expect(model.members.map(\.sourceOrder) == originalSourceOrder)
        let expansion = expandMacroSource("@DIContainer(\(Self.policy)) struct Container { \(members) }", macros: Self.macros)
        #expect(expansion.diagnostics.isEmpty)
        try expectBefore("var service: Service", "var value: Int", in: expansion.expansion)
        let overrides = try #require(try DIContainerCodeGenerator.generateAll(for: model)
            .compactMap { $0.as(StructDeclSyntax.self) }.first { $0.name.text == "Overrides" })
        let overrideNames = overrides.memberBlock.members.compactMap {
            $0.decl.as(VariableDeclSyntax.self)?.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
        }
        #expect(Array(overrideNames.prefix(3)) == ["service", "value", "seed"])
    }

    @Test("Ready set reconsiders lower declaration indices instead of FIFO")
    func stableReadyPriority() throws {
        let (model, declaration) = try parse("""
            @Provide(.shared, factory: 1) var a: Int
            @Provide(.shared, factory: { (a: Int) in a }) var b: Int
            @Provide(.shared, factory: 3) var c: Int
            """)
        try validate(model, declaration)
        #expect(try DIContainerInitializationPlan(model: model).syncShared.map(\.name) == ["a", "b", "c"])
    }

    @Test("Diamond and duplicate hard edges use stable topological order")
    func diamond() throws {
        let (model, declaration) = try parse("""
            @Provide(.shared, factory: { (left: Int, right: Int) in left + right }) var end: Int
            @Provide(.shared, factory: { (root: Int) in root }) var left: Int
            @Provide(.shared, factory: 0) var independent: Int
            @Provide(.shared, factory: { (root: Int) in root }) var right: Int
            @Provide(.shared, factory: 1) var root: Int
            """)
        try validate(model, declaration)
        #expect(try DIContainerInitializationPlan(model: model).syncShared.map(\.name)
            == ["independent", "root", "left", "right", "end"])
    }

    @Test("Async eager and on-demand forward references use planned task and cell bindings", arguments: [false, true])
    func asynchronousForwardEdges(onDemand: Bool) throws {
        let initialization = onDemand ? "initialization: .onDemand, " : ""
        let (model, declaration) = try parse("""
            @Provide(.shared, asyncFactory: { (dependency: Int) async throws in dependency + 1 }) var consumer: Int
            @Provide(.shared, \(initialization)asyncFactory: { (sync: Int) async in sync }) var dependency: Int
            @Provide(.shared, factory: 1) var sync: Int
            """)
        try validate(model, declaration)
        let plan = try DIContainerInitializationPlan(model: model)
        #expect(plan.syncShared.map(\.name) == ["sync"])
        #expect(plan.asyncShared.map(\.name) == ["dependency", "consumer"])
        let generated = try DIContainerCodeGenerator.generateInit(for: model).description
        try expectBefore("self._storage_sync =", onDemand ? "let _innoDIOnDemandAsync_dependency" : "let _innoDITask_dependency", in: generated)
        try expectBefore(onDemand ? "let _innoDIOnDemandAsync_dependency" : "let _innoDITask_dependency", "let _innoDITask_consumer", in: generated)
        #expect(generated.contains(onDemand ? "try await _innoDIOnDemandAsync_dependency.value()" : "await _innoDITask_dependency.value"))
        try DIContainerCodeGenerator.validateInitialization(for: model)
    }

    @Test("Mixed eager and on-demand sync chains preserve deferred factory branches", arguments: [false, true])
    func mixedSynchronousCells(consumerOnDemand: Bool) throws {
        let firstInitialization = consumerOnDemand ? "initialization: .onDemand, " : ""
        let secondInitialization = consumerOnDemand ? "" : "initialization: .onDemand, "
        let (model, declaration) = try parse("""
            @Provide(.shared, \(firstInitialization)factory: { (dependency: Int) in dependency + 1 }) var consumer: Int
            @Provide(.shared, \(secondInitialization)factory: 1) var dependency: Int
            """)
        try validate(model, declaration)
        #expect(try DIContainerInitializationPlan(model: model).syncShared.map(\.name) == ["dependency", "consumer"])
        let generated = try DIContainerCodeGenerator.generateInit(for: model).description
        if consumerOnDemand {
            #expect(generated.contains("_innoDIOnDemandDependency_dependency"))
            #expect(generated.contains("let _innoDIOnDemand_consumer"))
        } else {
            #expect(generated.contains("_innoDIOnDemand_dependency.value()"))
        }
        #expect(generated.contains("if let _innoDIOverride = consumer"))
        try DIContainerCodeGenerator.validateInitialization(for: model)
    }

    @Test("Deferred-only edges never constrain initialization order")
    func deferredOnlyEdges() throws {
        let (model, declaration) = try parse("""
            @Provide(.shared, factory: { (later: Lazy<Int>, transient: Provider<Int>) in 1 }) var first: Int
            @Provide(.shared, factory: 2) var later: Int
            @Provide(.transient, factory: 3) var transient: Int
            """)
        try validate(model, declaration)
        #expect(try DIContainerInitializationPlan(model: model).syncShared.map(\.name) == ["first", "later"])
        let generated = try DIContainerCodeGenerator.generateInit(for: model).description
        try expectBefore("self._storage_first =", "self._storage_later =", in: generated)
        try expectBefore("let _innoDILazyCell_later", "let _innoDILazyCell_transient", in: generated)
    }

    @Test("Named role, MainActor, child wiring and overrides coexist with construction order")
    func roleAndChildSurface() throws {
        let members = """
            @Provide(.shared, factory: { (seed: Int) in seed }) var value: Int
            @Provide(.shared, factory: 1) var seed: Int
            @SubContainer(scope: .shared, with: [\\Self.value]) var child: Child
            """
        let attribute = "@DIContainerRole(role: ContainerRole.component, mainActor: true, \(Self.policy))"
        let (model, declaration) = try parse(members, attribute: attribute)
        try validate(model, declaration)
        #expect(model.options.role == .component)
        #expect(model.options.mainActor)
        let generated = try DIContainerCodeGenerator.generateAll(for: model).map(\.description).joined(separator: "\n")
        try expectBefore("self._storage_seed =", "self._storage_value =", in: generated)
        try expectBefore("self._storage_value =", "self._storage_sub_child=", in: generated)
        #expect(generated.contains("@_Concurrency.MainActor"))
        #expect(generated.contains("childOverrides"))
        #expect(generated.contains("if let _innoDIOverride = value"))
    }

    @Test("Close dependency order is independent of construction policy and tracing order")
    func preservesLifetimeSupportOrder() throws {
        let (model, declaration) = try parse("""
            @Provide(.shared, initialization: .onDemand, asyncFactory: { (dependency: Int) async throws in dependency }) var consumer: Int
            @Provide(.shared, initialization: .onDemand, asyncFactory: { () async in 1 }) var dependency: Int
            @Provide(.shared, factory: { (last: Int) in last }) var first: Int
            @Provide(.shared, factory: 1) var last: Int
            """)
        try validate(model, declaration)
        let generated = try DIContainerCodeGenerator.generateAll(for: model).map(\.description).joined(separator: "\n")
        try expectBefore("self._innoDITraceOwner_first =", "self._innoDITraceOwner_last =", in: generated)
        #expect(model.asyncOnDemandMembers.map(\.name) == ["consumer", "dependency"])
        let function = try #require(try DIContainerCodeGenerator.generateAll(for: model)
            .compactMap { $0.as(FunctionDeclSyntax.self) }.first { $0.name.text == "closeAsyncProviders" })
        // Both construction policies close dependants first. Trace owner
        // assignments and the immutable source model retain declaration order.
        let (declarationModel, _) = try parse(declaration.memberBlock.members.description, attribute: "@DIContainer(validateDAG: false)")
        let defaultClose = try #require(try DIContainerCodeGenerator.generateAll(for: declarationModel)
            .compactMap { $0.as(FunctionDeclSyntax.self) }.first { $0.name.text == "closeAsyncProviders" })
        #expect(function.description == defaultClose.description)
    }

    @Test("On-demand teardown closes dependants before earlier declared dependencies")
    func closesDependentBeforeDependency() throws {
        let (model, declaration) = try parse("""
            @Provide(.shared, initialization: .onDemand, asyncFactory: { () async in 1 }) var dependency: Int
            @Provide(.shared, initialization: .onDemand, asyncFactory: { (dependency: Int) async throws in dependency }) var consumer: Int
            """)
        try validate(model, declaration)
        let function = try #require(try DIContainerCodeGenerator.generateAll(for: model)
            .compactMap { $0.as(FunctionDeclSyntax.self) }.first { $0.name.text == "closeAsyncProviders" })
        try expectBefore("self._storage_consumer!.close()", "self._storage_dependency!.close()", in: function.description)
    }

    @Test("Teardown includes dependency paths through eager providers without closing eager tasks")
    func closesAcrossEagerBridge() throws {
        let (model, declaration) = try parse("""
            @Provide(.shared, initialization: .onDemand, asyncFactory: { () async in 1 }) var dependency: Int
            @Provide(.shared, asyncFactory: { (dependency: Int) async throws in dependency }) var eager: Int
            @Provide(.shared, initialization: .onDemand, asyncFactory: { (eager: Int) async throws in eager }) var consumer: Int
            """)
        try validate(model, declaration)
        let function = try #require(try DIContainerCodeGenerator.generateAll(for: model)
            .compactMap { $0.as(FunctionDeclSyntax.self) }.first { $0.name.text == "closeAsyncProviders" })
        try expectBefore("self._storage_consumer!.close()", "self._storage_dependency!.close()", in: function.description)
        #expect(!function.description.contains("eager"))
    }

    @Test("Invalid tokens produce one anchored canonical diagnostic", arguments: [
        ".dependency", "\"dependency\"", "mode", "chooseMode()", "Other.ContainerInitializationOrder.dependency",
    ])
    func invalidTokenDiagnostic(_ expression: String) throws {
        let result = expandMacroSource("@DIContainer(initializationOrder: \(expression)) struct Container {}", macros: Self.macros)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics.first?.diagnosticID == code("container.initialization-order-token-required"))
        #expect(result.diagnostics.first?.node.trimmedDescription == expression)
    }

    @Test("Invalid order tokens diagnose once with providers in every container role", arguments: [
        "@DIContainer(",
        "@DIContainerRole(role: ContainerRole.local, ",
        "@DIContainerRole(role: ContainerRole.component, ",
        "@DIContainerRole(role: ContainerRole.root, ",
        "@DIContainerRole(role: ContainerRole.local, mainActor: true, ",
    ])
    func invalidTokenWithManagedMembers(_ prefix: String) {
        let result = expandMacroSource("""
            \(prefix)initializationOrder: ".dependency")
            struct Container {
                @Input var input: Int
                @Provide(.shared, factory: { (input: Int) in input }) var first: Int
                @Provide(.shared, asyncFactory: { (first: Int) async in first }) var second: Int
                @Provide(.transient, factory: { (first: Int) in first }) var third: Int
            }
            """, macros: Self.macros)
        #expect(result.diagnostics.map(\.diagnosticID) == [code("container.initialization-order-token-required")])
        #expect(result.diagnostics.first?.node.trimmedDescription == "\".dependency\"")
        #expect(!result.diagnostics.contains { $0.diagnosticID == code("internal.codegen-invariant") })
    }

    @Test("Mixed Provider ownership cycles still fail with dependency-order DAG opt-out")
    func mixedProviderCycle() {
        let result = expandMacroSource("""
            @DIContainer(validateDAG: false, \(Self.policy)) struct Container {
                @Provide(.shared, factory: { (second: Provider<Int>) in 1 }) var first: Int
                @Provide(.transient, factory: { (first: Lazy<Int>) in 2 }) var second: Int
            }
            """, macros: Self.macros)
        #expect(result.diagnostics.map(\.diagnosticID) == [code("container.dependency-cycle")])
    }

    @Test("Shared ordering diagnostics offer only valid forward-reference repairs", arguments: [false, true], [false, true])
    func sharedOrderingDiagnostic(targetBefore: Bool, usesWith: Bool) throws {
        for policy in ["declaration", "dependency"] {
            let consumer = usesWith
                ? "@Provide(.shared, Service.self, with: [\\Self.later]) var first: Service"
                : "@Provide(.shared, factory: { (later: Int) in later }) var first: Int"
            let provider = "@Provide(.shared, factory: 1) var later: Int"
            let source = """
                @DIContainer(initializationOrder: ContainerInitializationOrder.\(policy)) struct Container {
                    \(targetBefore ? provider : consumer)
                    \(targetBefore ? consumer : provider)
                }
                """
            let parsed = Parser.parse(source: source)
            let declaration = try #require(parsed.statements.first?.item.as(StructDeclSyntax.self))
            let attribute = try #require(declaration.attributes.first?.as(AttributeSyntax.self))
            let context = TestMacroExpansionContext()
            _ = try DIContainerMacro.expansion(of: attribute, providingMembersOf: declaration, in: context)
            if targetBefore || policy == "dependency" {
                #expect(context.diagnostics.isEmpty)
                continue
            }
            let diagnostic = try #require(context.diagnostics.first)
            #expect(context.diagnostics.count == 1)
            #expect(diagnostic.diagnosticID == code("provide.unavailable-dependency-reference"))
            #expect(diagnostic.diagMessage.severity == .error)
            #expect(diagnostic.message == "Dependency 'later' referenced by 'first' is not available in this declaration order.")
            #expect(diagnostic.notes.contains { $0.message.contains("Move shared provider 'later' before 'first'") })
            #expect(diagnostic.notes.contains { $0.message.contains("initializationOrder: ContainerInitializationOrder.dependency") })
            #expect(diagnostic.fixIts.isEmpty)
            let reference = usesWith ? "\\Self.later" : "later: Int)"
            let range = try #require(source.range(of: reference))
            let offset = source[..<range.lowerBound].utf8.count
            #expect(diagnostic.node.trimmedDescription == (usesWith ? "\\Self.later" : "later"))
            #expect(diagnostic.position.utf8Offset == offset)
        }
    }

    @Test("Transient hard scope errors identify the exact edge under either policy and order", arguments: [false, true], [false, true])
    func transientScopeDiagnostic(targetBefore: Bool, usesWith: Bool) throws {
        for policy in ["declaration", "dependency"] {
            let consumer = usesWith
                ? "@Provide(.shared, Service.self, with: [\\Self.transient]) var shared: Service"
                : "@Provide(.shared, factory: { (transient: Int) in transient }) var shared: Int"
            let provider = "@Provide(.transient, factory: 1) var transient: Int"
            let source = """
                @DIContainer(initializationOrder: ContainerInitializationOrder.\(policy)) struct Container {
                    \(targetBefore ? provider : consumer)
                    \(targetBefore ? consumer : provider)
                }
                """
            let parsed = Parser.parse(source: source)
            let declaration = try #require(parsed.statements.first?.item.as(StructDeclSyntax.self))
            let attribute = try #require(declaration.attributes.first?.as(AttributeSyntax.self))
            let context = TestMacroExpansionContext()
            let generated = try DIContainerMacro.expansion(of: attribute, providingMembersOf: declaration, in: context)
            let diagnostic = try #require(context.diagnostics.first)
            #expect(generated.isEmpty)
            #expect(context.diagnostics.count == 1)
            #expect(diagnostic.diagnosticID == code("provide.unavailable-dependency-reference"))
            #expect(diagnostic.diagMessage.severity == .error)
            #expect(diagnostic.message == "Dependency 'transient' referenced by 'shared' is not available in this construction scope because it is a transient provider.")
            #expect(diagnostic.notes.contains { $0.message.contains("changing declaration order cannot") })
            #expect(diagnostic.notes.contains { $0.message.contains("retained for later use") })
            #expect(!diagnostic.notes.contains { $0.message.contains("Move shared provider") || $0.message.contains("opt in") })
            #expect(diagnostic.fixIts.isEmpty)
            let reference = usesWith ? "\\Self.transient" : "transient: Int)"
            let range = try #require(source.range(of: reference))
            let offset = source[..<range.lowerBound].utf8.count
            #expect(diagnostic.node.trimmedDescription == (usesWith ? "\\Self.transient" : "transient"))
            #expect(diagnostic.node.kind == (usesWith ? .keyPathExpr : .token))
            #expect(diagnostic.node.positionAfterSkippingLeadingTrivia.utf8Offset == offset)
            #expect(diagnostic.position.utf8Offset == offset)
            let declarationNote = try #require(diagnostic.notes.first { $0.message == "'transient' is declared here." })
            let declarationRange = try #require(source.range(of: "var transient:"))
            #expect(declarationNote.node.trimmedDescription == "transient: Int")
            #expect(declarationNote.node.positionAfterSkippingLeadingTrivia.utf8Offset
                == source[..<declarationRange.lowerBound].utf8.count + 4)
        }
    }

    @Test("Async transient scope errors do not recommend synchronous deferred handles", arguments: [false, true], [false, true])
    func asyncTransientScopeDiagnostic(targetBefore: Bool, providerThrows: Bool) throws {
        for policy in ["declaration", "dependency"] {
            let effects = providerThrows ? "async throws" : "async"
            let consumer = "@Provide(.shared, asyncFactory: { (fresh: Int) \(effects) in fresh }) var shared: Int"
            let provider = "@Provide(.transient, asyncFactory: { () \(effects) in 1 }) var fresh: Int"
            let source = """
                @DIContainer(initializationOrder: ContainerInitializationOrder.\(policy)) struct Container {
                    \(targetBefore ? provider : consumer)
                    \(targetBefore ? consumer : provider)
                }
                """
            let parsed = Parser.parse(source: source)
            let declaration = try #require(parsed.statements.first?.item.as(StructDeclSyntax.self))
            let attribute = try #require(declaration.attributes.first?.as(AttributeSyntax.self))
            let context = TestMacroExpansionContext()
            let generated = try DIContainerMacro.expansion(of: attribute, providingMembersOf: declaration, in: context)
            let diagnostic = try #require(context.diagnostics.first)
            #expect(generated.isEmpty)
            #expect(context.diagnostics.count == 1)
            #expect(diagnostic.diagnosticID == code("provide.unavailable-dependency-reference"))
            #expect(diagnostic.notes.contains { $0.message.contains("async transient consumer with compatible throwing effects") })
            #expect(diagnostic.notes.contains { $0.message.contains("Lazy<T> and Provider<T> cannot wrap asynchronous targets") })
            #expect(!diagnostic.notes.contains { $0.message.contains("retained for later use") || $0.message.contains("Move shared provider") })
            #expect(diagnostic.fixIts.isEmpty)
            #expect(diagnostic.node.trimmedDescription == "fresh")
            let range = try #require(source.range(of: "fresh: Int)"))
            #expect(diagnostic.position.utf8Offset == source[..<range.lowerBound].utf8.count)
            #expect(diagnostic.notes.contains { $0.message == "'fresh' is declared here." })
        }
    }

    @Test("Cycles remain rejected with DAG diagnostics disabled", arguments: [true, false], ["Int", "Lazy<Int>"])
    func cycles(validateDAG: Bool, dependencyType: String) {
        let result = expandMacroSource("""
            @DIContainer(validateDAG: \(validateDAG), \(Self.policy)) struct Container {
                @Provide(.shared, factory: { (second: \(dependencyType)) in 1 }) var first: Int
                @Provide(.shared, factory: { (first: \(dependencyType)) in 2 }) var second: Int
            }
            """, macros: Self.macros)
        #expect(result.diagnostics.map(\.diagnosticID) == [code("container.dependency-cycle")])
    }

    @Test("Effect, unknown, duplicate and malformed wiring diagnostics are retained")
    func retainsValidationFailures() {
        let cases: [(String, String)] = [
            ("@Provide(.shared, factory: { (later: Int) in later }) var first: Int\n@Provide(.shared, asyncFactory: { () async in 1 }) var later: Int", "provide.async-dependency-requires-async-consumer"),
            ("@Provide(.shared, asyncFactory: { (later: Int) async in later }) var first: Int\n@Provide(.shared, initialization: .onDemand, asyncFactory: { () async in 1 }) var later: Int", "provide.throwing-dependency-requires-throwing-consumer"),
            ("@Provide(.shared, Service.self, with: [\\Self.later]) var first: Service\n@Provide(.shared, asyncFactory: { () async in 1 }) var later: Int", "provide.with-dependency-requires-synchronous-provider"),
            ("@Provide(.shared, factory: { (missing: Int) in missing }) var first: Int", "provide.unresolved-factory-parameter"),
            ("@Provide(.shared, Service.self, with: [\\Self.missing]) var first: Service", "provide.unresolved-with-dependency"),
            ("@Provide(.shared, factory: 1) var first: Int\n@Provide(.shared, factory: 2) var first: Int", "container.duplicate-member-name"),
            ("@Provide(.shared, Service.self, with: paths) var first: Service", "provide.invalid-with-dependencies"),
            ("@Provide(.shared, factory: { (later: Int, later: Int) in later }) var first: Int\n@Provide(.shared, factory: 1) var later: Int", "provide.duplicate-factory-parameter"),
        ]
        for (members, expected) in cases {
            let result = expandMacroSource("@DIContainer(\(Self.policy)) struct Container { \(members) }", macros: Self.macros)
            #expect(result.diagnostics.map(\.diagnosticID) == [code(expected)], "\(expected): \(result.diagnostics.map(\.message))")
        }
    }

    @Test("Dependency ordering removes false fallback qualifier conflicts under DAG opt-out")
    func forwardEdgesDoNotDemandTrapQualifier() {
        let result = expandMacroSource("""
            struct Outer {
                static let InnoDI = 0
                @DIContainer(validateDAG: false, \(Self.policy)) struct Container {
                    @Provide(.shared, factory: { (later: Int) in later }) var first: Int
                    @Provide(.shared, factory: 1) var later: Int
                }
            }
            """, macros: Self.macros)
        #expect(result.diagnostics.isEmpty)
        #expect(!result.expansion.contains("InnoDI._innoDITrap"))
    }

    @Test("Normalized opt-out references use the exact shared construction order", arguments: ["prior", "forward", "moved"])
    func normalizedFallbackQualifierParity(_ scenario: String) throws {
        let members: String
        let expectedOrder: [String]
        switch scenario {
        case "prior":
            members = """
                @Provide(.shared, factory: 1) var target: Int
                @Provide(.shared, factory: { (_storage_target: Int) in _storage_target }) var consumer: Int
                """
            expectedOrder = ["target", "consumer"]
        case "forward":
            members = """
                @Provide(.shared, factory: { (_storage_target: Int) in _storage_target }) var consumer: Int
                @Provide(.shared, factory: 1) var target: Int
                """
            expectedOrder = ["consumer", "target"]
        default:
            members = """
                @Provide(.shared, factory: { (later: Int) in later }) var target: Int
                @Provide(.shared, factory: { (_storage_target: Int) in _storage_target }) var consumer: Int
                @Provide(.shared, factory: 1) var later: Int
                """
            expectedOrder = ["consumer", "later", "target"]
        }
        let attribute = "@DIContainer(validateDAG: false, \(Self.policy))"
        let (model, declaration) = try parse(members, attribute: attribute)
        try validate(model, declaration)
        let requiresFallback = scenario != "prior"
        #expect(try DIContainerInitializationPlan(model: model).syncShared.map(\.name) == expectedOrder)
        let generated = try DIContainerCodeGenerator.generateInit(for: model).description
        #expect(generated.contains("InnoDI._innoDITrap") == requiresFallback)
        let usage = GeneratedQualifierUsage.container(declaration: declaration)
        #expect(usage.memberBodies.contains(.init("InnoDI", namespace: .typeOrValue)) == requiresFallback)
        try DIContainerCodeGenerator.validateInitialization(for: model)
        let expansion = expandMacroSource("""
            struct Outer {
                static let InnoDI = 0
                \(attribute) struct Container { \(members) }
            }
            """, macros: Self.macros)
        // Attached macro contexts intentionally do not inspect enclosing
        // member lists. The full-source preflight owns that shadow boundary;
        // this test proves the precise shared-core requirement it consumes.
        #expect(expansion.diagnostics.isEmpty)
    }

    @Test("Emission and preflight agree in dependency mode, including opt-out fallback")
    func codegenPreflightParity() throws {
        let fixtures = [
            "@Provide(.shared, factory: { (later: Int) in later }) var first: Int\n@Provide(.shared, factory: 1) var later: Int",
            "@Provide(.shared, factory: { (missing: Int) in missing }) var first: Int",
            "@Provide(.shared, factory: { (_storage_later: Int) in _storage_later }) var first: Int\n@Provide(.shared, factory: 1) var later: Int",
            "@Provide(.shared, factory: { (transient: Int) in transient }) var first: Int\n@Provide(.transient, factory: 1) var transient: Int",
            "@Provide(.shared, factory: { (second: Int) in second }) var first: Int\n@Provide(.shared, factory: { (first: Int) in first }) var second: Int",
        ]
        for validateDAG in [true, false] {
            for members in fixtures {
                let (model, _) = try parse(members, attribute: "@DIContainer(validateDAG: \(validateDAG), \(Self.policy))")
                let emittedError = errorDescription { _ = try DIContainerCodeGenerator.generateAll(for: model) }
                let preflightError = errorDescription { try DIContainerCodeGenerator.validateInitialization(for: model) }
                #expect(emittedError == preflightError)
                if !validateDAG && members.contains("missing") {
                    #expect(emittedError == nil)
                    #expect(try DIContainerCodeGenerator.generateInit(for: model).description.contains("_innoDITrap"))
                }
                if members.contains("var transient") && !validateDAG {
                    #expect(emittedError == nil)
                    #expect(try DIContainerCodeGenerator.generateInit(for: model).description.contains("transient ??"))
                }
                if members.contains("var second") { #expect(emittedError != nil) }
            }
        }
    }

    private func parse(_ members: String, attribute: String? = nil) throws -> (DIContainerExpansionModel, StructDeclSyntax) {
        let source = Parser.parse(source: "\(attribute ?? "@DIContainer(\(Self.policy))") struct Container { \(members) }")
        let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        let context = TestMacroExpansionContext()
        let model = try #require(DIContainerParser.parse(declaration: declaration, context: context))
        #expect(context.diagnostics.isEmpty)
        return (model, declaration)
    }

    private func validate(_ model: DIContainerExpansionModel, _ declaration: StructDeclSyntax) throws {
        let context = TestMacroExpansionContext()
        #expect(DIContainerValidator.validate(model: model, declaration: declaration, context: context),
                "\(context.diagnostics.map(\.message))")
        #expect(context.diagnostics.isEmpty)
    }

    private func code(_ value: String) -> MessageID { MessageID(domain: "InnoDI.validation", id: value) }

    private func expectBefore(_ first: String, _ second: String, in text: String) throws {
        let firstRange = try #require(text.range(of: first), "Missing \(first)")
        let secondRange = try #require(text.range(of: second), "Missing \(second)")
        #expect(firstRange.lowerBound < secondRange.lowerBound, "Expected \(first) before \(second)")
    }

    private func errorDescription(_ operation: () throws -> Void) -> String? {
        do { try operation(); return nil }
        catch let error as CodegenInvariantError { return error.description }
        catch { Issue.record("Unexpected error: \(error)"); return String(describing: error) }
    }
}
