import Foundation
import InnoDITestSupport
import SwiftBasicFormat
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("Explicit owned container generation")
struct OwnedContainerMacroTests {
    private static var macros: [String: any Macro.Type] {
        var macros = DIContainerMacroTests.macros
        macros["DIContainerRole"] = DIContainerRoleMacro.self
        return macros
    }

    @Test("Omitted and false options emit byte-identical legacy members")
    func defaultParity() {
        let body = """
            struct Container {
                @Input var input: Int
                @Provide(.shared, factory: { (input: Int) in input }) var sync: Int
                @Provide(.shared, asyncFactory: { () async in 2 }) var asyncValue: Int
            }
            """
        let omitted = expandMacroSource("@DIContainer " + body, macros: Self.macros)
        let disabled = expandMacroSource("@DIContainer(generateOwned: false) " + body, macros: Self.macros)
        #expect(omitted.diagnostics.isEmpty)
        #expect(disabled.diagnostics.isEmpty)
        #expect(omitted.expansion == disabled.expansion)
        #expect(!omitted.expansion.contains("makeOwned"))
    }

    @Test("Owned cells are concrete, eager launch is awaited, and source closure effects stay unchanged")
    func concreteConstruction() throws {
        let declarations = try owned("""
            @DIContainer(generateOwned: true) struct Container {
                @Input var input: Int
                @Provide(.shared, initialization: .onDemand, factory: { (input: Int) in input }) var lazy: Int
                @Provide(.shared, asyncFactory: { (lazy: Int) async in lazy }) var first: Int
                @Provide(.shared, asyncFactory: { (first: Int) async in first + 1 }) var second: Int
                @Provide(.shared, initialization: .onDemand, asyncFactory: { () async in 3 }) var deferred: Int
            }
            """)
        let text = declarations.map { $0.formatted().description }.joined(separator: "\n")
        #expect(text.contains("InnoDI.DIAsyncScope<Int>"))
        #expect(text.contains("InnoDI._InnoDISendableSharedCell<Int>"))
        #expect(text.contains("let _innoDIArgument_first = try await _innoDITraceOwner.withWait"))
        #expect(text.contains("try await _innoDIScope_first.value()"))
        #expect(text.contains("(first: Int) async in"))
        #expect(!text.contains("(first: Int) async throws in"))
        #expect(text.contains("_ = try await _innoDIScope_first.start()"))
        #expect(text.contains("_ = try await _innoDIScope_second.start()"))
        #expect(!text.contains("_innoDIScope_deferred.start()"))
        #expect(!text.contains("Task {"))
        #expect(!text.contains("Task.detached"))
        #expect(!text.contains("@unchecked"))
        #expect(!text.contains("AnyHashable"))
        #expect(text.contains("dependencies: second == nil ? [\"first\"] : []"))
        #expect(text.contains("await _innoDICoordinator.close()"))
    }

    @Test("Tokens contain only owned async providers, with no natural type aliases")
    func selections() throws {
        let declarations = try owned("""
            @DIContainer(generateOwned: true) struct Container {
                @Input var input: Int
                @Provide(.shared, factory: 1) var sync: Int
                @Provide(.shared, initialization: .onDemand, factory: 2) var lazy: Int
                @Provide(.shared, asyncFactory: { () async in 3 }) var service: Int
            }
            """)
        let selection = try #require(declarations.first?.as(EnumDeclSyntax.self))
        #expect(selection.name.text == "_InnoDIOwnedProvider")
        let cases = selection.memberBlock.members.compactMap { $0.decl.as(EnumCaseDeclSyntax.self)?.elements.first?.name.text }
        #expect(cases == ["service"])
        let source = declarations.map(\.description).joined()
        #expect(!source.contains("typealias Owner"))
        #expect(!source.contains("typealias OwnedView"))
        #expect(!source.contains("typealias OwnedProvider"))
        #expect(!source.contains("RawRepresentable"))
        #expect(!source.contains("struct _InnoDIOwner: Sendable"))
        #expect(!source.contains("struct _InnoDIOwnedView: Sendable"))
        #expect(source.contains("case .service: await _innoDIScope_service.cancel()"))
        #expect(!source.contains("await self."))
    }

    @Test("Owned override convenience reuses the existing builder before forwarding any construction", arguments: [false, true])
    func overridesBuilder(mainActor: Bool) throws {
        let declarations = try owned("""
            @DIContainerRole(role: ContainerRole.local, mainActor: \(mainActor), generateOwned: true)
            struct Container {
                @Input var action: () -> Int
                @Provide(.shared, factory: { (action: () -> Int) in action() }) var value: Int
                @Provide(.transient, factory: Optional<Int>.none) var optional: Int?
            }
            """)
        let functions = declarations.compactMap { $0.as(FunctionDeclSyntax.self) }
        #expect(functions.count == 2)
        let convenience = try #require(functions.first)
        #expect(convenience.name.text == "makeOwnedWithOverrides")
        #expect(convenience.signature.parameterClause.parameters.map(\.firstName.text) == ["action", "_innoDITrace", "_"])
        let source = convenience.formatted().description
        #expect(source.contains("(inout Self.Overrides) throws -> Void"))
        let builderType = try #require(convenience.signature.parameterClause.parameters.last?.type.description)
        #expect(!builderType.contains("@escaping"))
        #expect(!builderType.contains("@Sendable"))
        let body = try #require(convenience.body)
        #expect(body.statements.count == 4)
        #expect(body.statements.first?.description.contains("Task.checkCancellation()") == true)
        #expect(body.statements.dropFirst().first?.description.contains("Self.Overrides()") == true)
        #expect(body.statements.dropFirst(2).first?.description.contains("try _innoDIApplyOverrides") == true)
        #expect(body.statements.last?.description.contains("return try await Self.makeOwned") == true)
        #expect(source.contains("value: _innoDIOverrides.value"))
        #expect(source.contains("optional: _innoDIOverrides.optional"))
        #expect(!source.contains("_InnoDIAsyncAdmission()"))
        #expect(!source.contains("_innoDICell_"))
        #expect(source.contains("@_Concurrency.MainActor") == mainActor)
        #expect(source.contains("nonisolated(nonsending)") != mainActor)
    }

    @Test("Factory order may change while the signature and selection keep source order")
    func dependencyOrder() throws {
        let declarations = try owned("""
            @DIContainer(initializationOrder: ContainerInitializationOrder.dependency, generateOwned: true)
            struct Container {
                @Provide(.shared, asyncFactory: { (first: Int) async in first }) var second: Int
                @Provide(.shared, asyncFactory: { () async in 1 }) var first: Int
            }
            """)
        let factory = try #require(declarations.last?.as(FunctionDeclSyntax.self))
        #expect(factory.signature.parameterClause.parameters.map(\.firstName.text) == ["second", "first", "_innoDITrace"])
        let body = try #require(factory.body?.description)
        let first = try #require(body.range(of: "let _innoDIScope_first:"))
        let second = try #require(body.range(of: "let _innoDIScope_second:"))
        #expect(first.lowerBound < second.lowerBound)
        let view = try #require(body.range(of: "let _innoDIView"))
        let start = try #require(body.range(of: "_ = try await _innoDIScope_first.start()"))
        #expect(view.lowerBound < start.lowerBound)
    }

    @Test("Self types are rewritten only for the nested view; factory bodies keep original lexical context")
    func lexicalSelf() throws {
        let declarations = try owned("""
            @DIContainer(generateOwned: true) struct Container {
                enum Value: Sendable { case service }
                static func build() -> Value { .service }
                @Provide(.shared, asyncFactory: { () async -> Self.Value in Self.build() }) var service: Self.Value
            }
            """)
        let view = try #require(declarations.compactMap { $0.as(StructDeclSyntax.self) }
            .first { $0.name.text == "_InnoDIOwnedView" }).formatted().description
        let factory = try #require(declarations.last?.as(FunctionDeclSyntax.self)).formatted().description
        #expect(view.contains("DIAsyncScope<_InnoDIOwnedSelf.Value>"))
        #expect(view.contains("var service: _InnoDIOwnedSelf.Value"))
        #expect(factory.contains("async -> Self.Value in"))
        #expect(factory.contains("Self.build()"))
        #expect(!view.contains("static func build"))
    }

    @Test("MainActor is explicit and caller-isolated owners never require Sendable")
    func isolation() throws {
        let source = """
            @DIContainerRole(role: ContainerRole.local, mainActor: true, generateOwned: true)
            struct Container {
                @Provide(.shared, asyncFactory: { () async in 1 }) var service: Int
            }
            """
        let declarations = try owned(source)
        #expect(declarations[1].description.contains("@_Concurrency.MainActor"))
        #expect(declarations[2].description.contains("@_Concurrency.MainActor"))
        #expect(declarations[3].description.contains("@_Concurrency.MainActor"))
        #expect(!declarations[2].description.contains("nonisolated(nonsending)"))
        let caller = try owned(source.replacingOccurrences(of: "mainActor: true", with: "mainActor: false"))
        #expect(caller[2].description.contains("nonisolated(nonsending) func close"))
        #expect(caller[3].description.contains("nonisolated(nonsending) static func makeOwned"))
    }

    @Test("Shared children use typed existing wiring and are not lifecycle nodes")
    func borrowedChildren() throws {
        let declarations = try owned("""
            @DIContainer(generateOwned: true) struct Container {
                @Input var value: Int
                @SubContainer(scope: .shared, with: [\\Self.value]) var child: Child
            }
            """)
        let factory = try #require(declarations.last).formatted().description
        #expect(factory.contains("childOverrides"))
        #expect(factory.contains(".init(value: value, _innoDITrace: _innoDITrace"))
        #expect(factory.contains("nodes: []"))
        #expect(!factory.contains("child.close"))
    }

    @Test("Unsupported owned shapes receive anchored diagnostics", arguments: [
        "@Provide(.transient, asyncFactory: { () async in 1 }) var value: Int",
        "@Input(.assisted) var value: Int",
        "@SubContainer(scope: .transient, with: []) var child: Child"
    ])
    func unsupported(_ body: String) {
        let result = expandMacroSource("@DIContainer(generateOwned: true) struct Container { \(body) }", macros: Self.macros)
        #expect(result.diagnostics.contains { $0.message.contains("generateOwned: true does not yet support") })
        #expect(!result.expansion.contains("static func makeOwned"))
    }

    @Test("Owned deferred targets use typed non-Sendable cells without changing preparation nodes")
    func deferredTargets() throws {
        let declarations = try owned("""
            @DIContainer(generateOwned: true) struct Container {
                @Input var input: Int
                @Provide(.shared, factory: { (later: Lazy<Int>) in Holder(later) }) var first: Holder
                @Provide(.shared, initialization: .onDemand, factory: 2) var later: Int
                @Provide(.transient, factory: { (fresh: Provider<Int>, input: Lazy<Int>) in Holder(fresh, input) }) var holder: Holder
                @Provide(.transient, factory: 3) var fresh: Int
                @Provide(.shared, asyncFactory: { () async in 4 }) var asyncValue: Int
            }
            """)
        let factory = try #require(declarations.last?.as(FunctionDeclSyntax.self))
        let body = try #require(factory.body?.description)
        #expect(body.components(separatedBy: "final class _InnoDIDeferredCell").count == 2)
        #expect(!body.contains("@unchecked"))
        #expect(!body.contains("class _InnoDIDeferredCell<T>:"))
        for name in ["input", "later", "fresh"] {
            #expect(body.components(separatedBy: "let _innoDILazyCell_\(name) =").count == 2)
        }
        #expect(body.contains("_innoDILazyCell_input.storeValue(input)"))
        #expect(body.contains("_innoDILazyCell_later.bindResolver { _innoDICell_later.value() }"))
        #expect(body.contains("_innoDILazyCell_fresh.bindResolver(_innoDIResolver_fresh)"))
        let binding = try #require(body.range(of: "_innoDILazyCell_fresh.bindResolver"))
        let admission = try #require(body.range(of: "_ = try await _innoDIScope_asyncValue.start()"))
        #expect(binding.lowerBound < admission.lowerBound)
        let selection = try #require(declarations.first?.as(EnumDeclSyntax.self))
        #expect(selection.memberBlock.members.compactMap { $0.decl.as(EnumCaseDeclSyntax.self)?.elements.first?.name.text } == ["asyncValue"])
    }

    @Test("Per-member actor isolation is rejected before a weaker owned view can be emitted")
    func memberActorIsolation() {
        let result = expandMacroSource("""
            @DIContainer(generateOwned: true) struct Container {
                @MainActor @Input var value: Int
            }
            """, macros: Self.macros)
        // The existing closed property-shape validator can reject this before
        // owned validation. Keep that anchored earlier diagnostic authoritative.
        #expect(!result.diagnostics.isEmpty)
        #expect(!result.expansion.contains("static func makeOwned"))
        #expect(result.diagnostics.contains { $0.message.contains("@Input") || $0.message.contains("@Provide") || $0.message.contains("global-actor") })
    }

    @Test("Owned construction requires a literal option, full DAG validation, and a free public name", arguments: [
        ("generateOwned: flag", "", "requires a literal true or false"),
        ("validateDAG: false, generateOwned: true", "", "requires validateDAG: true"),
        ("generateOwned: true", "func makeOwned() {}", "already uses 'makeOwned'"),
        ("generateOwned: true", "static var makeOwned: Int { 1 }", "already uses 'makeOwned'"),
        ("generateOwned: true", "struct makeOwned {}", "already uses 'makeOwned'"),
        ("generateOwned: true", "typealias makeOwned = Int", "already uses 'makeOwned'"),
        ("generateOwned: true", "func makeOwnedWithOverrides() {}", "already uses 'makeOwnedWithOverrides'"),
        ("generateOwned: true", "struct makeOwnedWithOverrides {}", "already uses 'makeOwnedWithOverrides'")
    ])
    func optInDiagnostics(_ fixture: (String, String, String)) {
        let result = expandMacroSource("@DIContainer(\(fixture.0)) struct Container { \(fixture.1) }", macros: Self.macros)
        #expect(result.diagnostics.contains { $0.message.contains(fixture.2) })
    }

    @Test("Legacy containers may keep a nested makeOwned type", arguments: ["@DIContainer", "@DIContainer(generateOwned: false)"])
    func legacyMakeOwnedName(_ attribute: String) {
        let result = expandMacroSource("\(attribute) struct Container { struct makeOwned {} }", macros: Self.macros)
        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("struct makeOwned"))
        #expect(!result.expansion.contains("static func makeOwned"))
    }

    @Test("Empty and input-only owners omit uninhabited selection APIs", arguments: [
        "", "@Input var input: Int", "@Provide(.shared, factory: 1) var value: Int"
    ])
    func noAsyncSelections(_ body: String) throws {
        let declarations = try owned("@DIContainer(generateOwned: true) struct Container { \(body) }")
        #expect(declarations.count == 4)
        let text = declarations.map(\.description).joined(separator: "\n")
        #expect(!text.contains("_InnoDIOwnedProvider"))
        #expect(!text.contains("func prepare("))
        #expect(!text.contains("func retry("))
        #expect(!text.contains("func cancel("))
        #expect(!text.contains("func status("))
        #expect(text.contains("func close()"))
        #expect(text.contains("static func makeOwned"))
    }

    @Test("Owned generation retains source graph cycle and factory-effect validation")
    func graphAndEffectValidation() {
        let cyclic = expandMacroSource("""
            @DIContainer(initializationOrder: ContainerInitializationOrder.dependency, generateOwned: true)
            struct Container {
                @Provide(.shared, asyncFactory: { (second: Int) async in second }) var first: Int
                @Provide(.shared, asyncFactory: { (first: Int) async in first }) var second: Int
            }
            """, macros: Self.macros)
        #expect(cyclic.diagnostics.contains { $0.message.lowercased().contains("cycle") })
        #expect(!cyclic.expansion.contains("static func makeOwned"))
        let effects = expandMacroSource("""
            @DIContainer(generateOwned: true) struct Container {
                @Provide(.shared, asyncFactory: { () async throws in 1 }) var first: Int
                @Provide(.shared, asyncFactory: { (first: Int) async in first }) var second: Int
            }
            """, macros: Self.macros)
        #expect(effects.diagnostics.contains { $0.message.contains("throws") || $0.message.contains("throwing") })
        #expect(!effects.expansion.contains("static func makeOwned"))
    }

    @Test("Owned-only runtime qualifiers fail at the authored collision", arguments: ["InnoDI", "_Concurrency"])
    func runtimeQualifierCollision(_ name: String) {
        let result = expandMacroSource("@DIContainer(generateOwned: true) struct Container { @Input var \(name): Int }", macros: Self.macros)
        #expect(result.diagnostics.contains { $0.message.contains("\(name)") && $0.message.contains("module") })
        #expect(!result.expansion.contains("static func makeOwned"))
    }

    @Test("Self types bind through an outer compiler witness, not a shadowable name")
    func selfTypeWitness() throws {
        let declarations = try owned("""
            @DIContainer(generateOwned: true) public struct Same {
                struct Same {}
                @Input var factory: () -> Self
            }
            """)
        let alias = try #require(declarations.first?.as(TypeAliasDeclSyntax.self))
        #expect(alias.name.text == "_InnoDIOwnedSelf")
        #expect(alias.modifiers.first?.name.text == "public")
        #expect(alias.initializer.value.trimmedDescription == "Self")
        let text = declarations.map(\.description).joined(separator: "\n")
        #expect(text.contains("() -> _InnoDIOwnedSelf"))
        #expect(!text.contains("() -> Same"))
        let plain = try owned("@DIContainer(generateOwned: true) struct Plain { @Input var value: Int }")
        #expect(!plain.contains { $0.is(TypeAliasDeclSyntax.self) })
    }

    @Test("Authored owned witness names keep the reserved-prefix diagnostic")
    func witnessNameCollision() {
        let result = expandMacroSource("""
            @DIContainer(generateOwned: true) struct Container {
                typealias _InnoDIOwnedSelf = Int
                @Input var factory: () -> Self
            }
            """, macros: Self.macros)
        #expect(result.diagnostics.contains { $0.message.contains("reserved") })
        #expect(result.diagnostics.contains { $0.node.trimmedDescription == "_InnoDIOwnedSelf" })
        #expect(!result.expansion.contains("static func makeOwned"))
    }

    @Test("Synchronous transients compose without lifecycle nodes or repeated diamond code")
    func synchronousTransients() throws {
        let declarations = try owned("""
            @DIContainer(generateOwned: true) struct Container {
                @Input var seed: Int
                @Provide(.shared, initialization: .onDemand, factory: { (seed: Int) in seed }) var root: Int
                @Provide(.transient, factory: { (root: Int) in root + 1 }) var leaf: Int
                @Provide(.transient, factory: { (leaf: Int) in leaf + 2 }) var left: Int
                @Provide(.transient, factory: { (leaf: Int) in leaf + 3 }) var right: Int
                @Provide(.transient, factory: { (left: Int, right: Int) in left + right }) var result: Int
            }
            """)
        let factory = try #require(declarations.last?.as(FunctionDeclSyntax.self))
        #expect(factory.signature.parameterClause.parameters.map(\.firstName.text) == [
            "seed", "root", "leaf", "left", "right", "result", "_innoDITrace"
        ])
        let text = declarations.map(\.description).joined(separator: "\n")
        #expect(!text.contains("_InnoDIOwnedProvider"))
        #expect(!text.contains("DIAsyncScope<"))
        #expect(!text.contains("Task {"))
        #expect(!text.contains("@unchecked"))
        let resolvers = factory.body?.statements.compactMap { $0.item.as(VariableDeclSyntax.self) }
            .filter { $0.bindings.first?.pattern.trimmedDescription.hasPrefix("_innoDIResolver_") == true } ?? []
        #expect(resolvers.count == 4)
        for resolver in resolvers {
            let body = try #require(resolver.bindings.first?.initializer?.value.as(ClosureExprSyntax.self))
            #expect(!body.description.contains("_innoDIOwner"))
            #expect(!body.description.contains("_innoDICoordinator"))
            #expect(!body.description.contains("_innoDIAdmission"))
            #expect(body.description.contains("if let _innoDIOverride"))
        }
        #expect(text.components(separatedBy: "root + 1").count == 2)
        #expect(text.contains("_innoDIResolver_leaf()"))
        #expect(text.contains("_innoDICell_root.value()"))
    }

    @Test("Shared async providers cannot capture synchronous transient resolvers", arguments: [false, true])
    func sharedTransientDependency(mainActor: Bool) {
        let result = expandMacroSource("""
            @DIContainerRole(role: ContainerRole.local, mainActor: \(mainActor), generateOwned: true) struct Container {
                @Provide(.transient, factory: 1) var fresh: Int
                @Provide(.shared, asyncFactory: { (fresh: Int) async in fresh }) var service: Int
            }
            """, macros: Self.macros)
        #expect(result.diagnostics.contains { $0.message.contains("is not available in this declaration order or scope") })
        #expect(!result.expansion.contains("static func makeOwned"))
    }

    private func owned(_ source: String) throws -> [DeclSyntax] {
        let parsed = Parser.parse(source: source)
        let declaration = try #require(parsed.statements.first?.item.as(StructDeclSyntax.self))
        let context = TestMacroExpansionContext()
        let model = try #require(DIContainerParser.parse(declaration: declaration, context: context))
        #expect(context.diagnostics.isEmpty)
        #expect(DIContainerValidator.validate(model: model, declaration: declaration, context: context))
        #expect(context.diagnostics.isEmpty)
        let result = try makeOwnedContainerDecls(model: model)
        let hasSelf = (model.members.map(\.type) + model.subContainerMembers.map(\.type))
            .contains { $0.tokens(viewMode: .sourceAccurate).contains { $0.text == "Self" } }
        #expect(result.count == (model.asyncSharedMembers.isEmpty ? 4 : 6) + (hasSelf ? 1 : 0))
        return result
    }
}
