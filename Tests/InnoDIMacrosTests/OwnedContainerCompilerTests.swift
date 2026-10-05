import Foundation
import InnoDITestSupport
import SwiftBasicFormat
import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDIMacros

/// Compile the actual emitted owned surface against a portable module built
/// from production runtime sources. No substitute scope, owner, tracing or
/// shared-cell implementations are used. Portable positive fixtures contain
/// the coexisting legacy initializer, Overrides, and actual peer/accessor output.
/// Linux's async-on-demand Controlled fixture and Self.Value view witness are
/// explicitly narrower owned-only cases; this does not qualify the actual macro
/// plugin, Apple os runtime, or a complete package build. The tiny trap declaration is copied
/// verbatim from its syntax node because the remainder of InnoDI.swift declares
/// compiler macros, which this already-expanded canary does not load.
@Suite("Owned container generated-surface compiler checks")
struct OwnedContainerCompilerTests {
    @Test("Real generated factories and lifecycle methods typecheck and execute with the actual runtime")
    func actualOwnedSurface() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let runtime = root.appendingPathComponent("Sources/InnoDI")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnoDI-Owned-Compiler-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let publicSource = Parser.parse(source: try String(contentsOf: runtime.appendingPathComponent("InnoDI.swift"), encoding: .utf8))
        let trap = try #require(publicSource.statements.compactMap { $0.item.as(FunctionDeclSyntax.self) }
            .first { $0.name.text == "_innoDITrap" })
        let trapFile = directory.appendingPathComponent("Trap.swift")
        try trap.description.write(to: trapFile, atomically: true, encoding: .utf8)
        #if os(macOS)
        let library = directory.appendingPathComponent("libInnoDI.dylib")
        #else
        let library = directory.appendingPathComponent("libInnoDI.so")
        #endif
        var runtimeFiles = ["DIAsyncScope.swift", "DIAsyncOwner.swift", "DITracing.swift", "OnDemandSharedCell.swift"]
        #if canImport(os)
        runtimeFiles.append("AsyncSharedCell.swift")
        #endif
        let runtimeResult = try swift([
            "-emit-module", "-emit-library", "-module-name", "InnoDI", "-o", library.path,
            "-emit-module-path", directory.appendingPathComponent("InnoDI.swiftmodule").path,
        ] + runtimeFiles.map { runtime.appendingPathComponent($0).path } + [trapFile.path])
        #expect(!runtimeResult.timedOut, Comment(rawValue: runtimeResult.combinedOutput))
        #expect(runtimeResult.exitCode == 0, Comment(rawValue: runtimeResult.combinedOutput))
        guard runtimeResult.exitCode == 0, !runtimeResult.timedOut else { return }

        // Existing legacy scaffolding has a separate Self-in-Overrides bug.
        // Pin a full-source negative canary without the owned opt-in so that
        // owned type rewriting cannot accidentally mask or inherit that bug.
        let legacySelf = try fullyEmitted("""
            @DIContainer struct LegacySelf {
                enum Value { case service }
                @Provide(.shared, factory: Value.service) var service: Self.Value
            }
            """)
        let legacySelfFile = directory.appendingPathComponent("LegacySelf.swift")
        try ("import InnoDI\n" + legacySelf).write(to: legacySelfFile, atomically: true, encoding: .utf8)
        let legacySelfResult = try swift(["-typecheck", "-I", directory.path, legacySelfFile.path])
        #expect(legacySelfResult.exitCode != 0)
        #expect(legacySelfResult.combinedOutput.contains("Overrides") && legacySelfResult.combinedOutput.contains("Value"),
                Comment(rawValue: legacySelfResult.combinedOutput))

        let empty = try fullyEmitted("@DIContainer(generateOwned: true) struct Empty {}")
        let caller = try fullyEmitted("""
            @DIContainer(generateOwned: true) struct Caller {
                @Input var local: LocalValue
                @Provide(.shared, initialization: .onDemand, factory: { (local: LocalValue) in local }) var lazy: LocalValue
            }
            """)
        let chain = try fullyEmitted("""
            @DIContainer(initializationOrder: ContainerInitializationOrder.dependency, generateOwned: true)
            struct Chain {
                @Input var input: Int
                @Provide(.shared, asyncFactory: { (first: Int) async in first + 1 }) var second: Int
                @Provide(.shared, asyncFactory: { (lazy: Int) async in lazy }) var first: Int
                @Provide(.shared, initialization: .onDemand, factory: { (input: Int) in input }) var lazy: Int
                @Provide(.shared, asyncFactory: { () async in Owner.service }) var ownerPayload: Owner
                @Provide(.shared, asyncFactory: { () async in OwnedView.service }) var viewPayload: OwnedView
                @Provide(.shared, asyncFactory: { () async in OwnedProvider.service }) var providerPayload: OwnedProvider
            }
            """)
        let isolated = try fullyEmitted("""
            @DIContainerRole(role: ContainerRole.local, mainActor: true, generateOwned: true)
            struct Isolated {
                @Input var local: LocalValue
                @Provide(.shared, initialization: .onDemand, factory: { (local: LocalValue) in local }) var lazy: LocalValue
                @Provide(.shared, asyncFactory: { () async -> Self.Value in Self.build() }) var service: Value
            }
            """, support: """
                enum Value: Sendable { case service }
                @MainActor static func build() -> Value { .service }
                """)
        let pairedFalse = try fullyEmitted("""
            @DIContainer(generateOwned: false) struct PairedFalse {
                @Input var input: Int
                @Provide(.shared, factory: { (input: Int) in input + 1 }) var value: Int
            }
            """)
        let pairedTrue = try fullyEmitted("""
            @DIContainer(generateOwned: true) struct PairedTrue {
                @Input var input: Int
                @Provide(.shared, factory: { (input: Int) in input + 1 }) var value: Int
            }
            """)
        // Narrow owned-only witness for TypeSyntax rewriting of Self.Value.
        // Full legacy Self.Value coexistence is the negative canary above.
        let selfView = try emitted("""
            @DIContainer(generateOwned: true) struct SelfView {
                @Provide(.shared, asyncFactory: { () async -> Self.Value in Self.build() }) var service: Self.Value
            }
            """, support: """
                enum Value: Sendable { case service }
                static func build() -> Value { .service }
                """)
        // Linux: this is intentionally an owned-surface runtime canary.
        // The coexisting legacy on-demand async cell imports Apple os; do not
        // replace it with a behavior stub to imply full-package qualification.
        let controlledSource = """
            @DIContainer(generateOwned: true) struct Controlled {
                @Input var gate: ControlledGate
                @Provide(.shared, asyncFactory: { (gate: ControlledGate) async in await gate.value() }) var a: Int
                @Provide(.shared, asyncFactory: { () async in 9 }) var ready: Int
                @Provide(.shared, initialization: .onDemand, asyncFactory: { () async in 10 }) var idle: Int
            }
            """
        #if canImport(os)
        let controlled = try fullyEmitted(controlledSource)
        #else
        let controlled = try emitted(controlledSource)
        #endif
        let borrowed = try fullyEmitted("""
            @DIContainer(generateOwned: true) struct Borrowing {
                @Input var input: Int
                @SubContainer(scope: .shared, with: [\\Self.input]) var child: Child
            }
            """)
        let child = try fullyEmitted("@DIContainer struct Child { @Input var input: Int }")
        let source = """
            import InnoDI
            final class LocalValue {}
            enum Owner: Sendable { case service }
            enum OwnedView: Sendable { case service }
            enum OwnedProvider: Sendable { case service }
            actor ControlledGate {
                private var calls = 0
                private var firstStarted: [CheckedContinuation<Void, Never>] = []
                private var firstRelease: CheckedContinuation<Void, Never>?

                func value() async -> Int {
                    calls += 1
                    if calls == 1 {
                        let waiting = firstStarted
                        firstStarted.removeAll()
                        for waiter in waiting { waiter.resume() }
                        await withCheckedContinuation { firstRelease = $0 }
                        return 111
                    }
                    return 222
                }

                func waitForFirstStart() async {
                    if calls > 0 { return }
                    await withCheckedContinuation { firstStarted.append($0) }
                }

                func releaseFirst() {
                    firstRelease?.resume()
                    firstRelease = nil
                }
            }

            actor CancellationTrace: DITraceSink {
                private var sawCancellation = false
                private var waiters: [CheckedContinuation<Void, Never>] = []
                nonisolated func record(_ event: DITraceEvent) {
                    if event.kind == .cancel && event.providerID.hasSuffix(".a") {
                        Task { await self.markCancellation() }
                    }
                }
                private func markCancellation() {
                    sawCancellation = true
                    let waiting = waiters
                    waiters.removeAll()
                    for waiter in waiting { waiter.resume() }
                }
                func waitForCancellation() async {
                    if sawCancellation { return }
                    await withCheckedContinuation { waiters.append($0) }
                }
            }
            \(empty)
            \(pairedFalse)
            \(pairedTrue)
            \(selfView)
            \(caller)
            \(chain)
            \(isolated)
            \(controlled)
            \(child)
            \(borrowed)

            @main struct Check {
                @MainActor static func main() async throws {
                    let legacyFalse = PairedFalse(input: 1)
                    let legacyTrue = PairedTrue(input: 1)
                    precondition(legacyFalse.value == 2 && legacyTrue.value == 2)
                    let paired = try await PairedTrue.makeOwned(input: 1)
                    precondition(paired.container.value == legacyTrue.value)
                    await paired.close()
                    let typedSelf = try await SelfView.makeOwned()
                    let _: SelfView.Value = try await typedSelf.container.service
                    await typedSelf.close()
                    let empty = try await Empty.makeOwned()
                    await empty.close()
                    let value = LocalValue()
                    let caller = try await Caller.makeOwned(local: value)
                    precondition(caller.container.lazy === value)
                    let escaped = caller.container
                    await caller.close()
                    precondition(escaped.lazy === value)

                    let trace = DIBoundedTraceBuffer(capacity: 64)
                    let owner = try await Chain.makeOwned(input: 4, _innoDITrace: .init(sink: trace))
                    let report = try await owner.prepare(.second)
                    precondition(report.isReady)
                    let second = try await owner.container.second
                    precondition(second == 5)
                    let _: Owner = try await owner.container.ownerPayload
                    let _: OwnedView = try await owner.container.viewPayload
                    let _: OwnedProvider = try await owner.container.providerPayload
                    let snapshot = trace.snapshot().events
                    precondition(snapshot.contains { $0.kind == .start })
                    precondition(snapshot.contains { $0.kind == .success })
                    let copy = owner
                    await copy.cancel(.first, .second)
                    let ready = await owner.status(.second)
                    precondition(ready.state == .ready)
                    await copy.close()
                    let closed = await owner.status(.second)
                    precondition(closed.state == .closed)
                    do {
                        _ = try await owner.container.second
                        preconditionFailure("escaped view must observe close")
                    } catch DIAsyncScopeError.closed(providerID: "second") {}

                    let overridden = try await Chain.makeOwned(input: 4, second: 42)
                    let selected = try await overridden.prepare(.second)
                    precondition(selected.entries.map(\\.providerID) == ["second"])
                    let replacement = try await overridden.container.second
                    precondition(replacement == 42)
                    await overridden.close()

                    let isolated = try await Isolated.makeOwned(local: value)
                    let _: Isolated.Value = try await isolated.container.service
                    precondition(isolated.container.lazy === value)
                    await isolated.close()

                    let gate = ControlledGate()
                    let cancellationTrace = CancellationTrace()
                    let running = try await Controlled.makeOwned(gate: gate, _innoDITrace: .init(sink: cancellationTrace))
                    await gate.waitForFirstStart()
                    let initialRunning = await running.status(.a)
                    precondition(initialRunning.state == .running)
                    let unrelatedReady = try await running.container.ready
                    precondition(unrelatedReady == 9)
                    let initialIdle = await running.status(.idle)
                    precondition(initialIdle.state == .idle)
                    await running.cancel(.a)
                    let cancelled = await running.status(.a)
                    precondition(cancelled.state == .cancelled)
                    let stillReady = try await running.container.ready
                    precondition(stillReady == 9)
                    let stillIdle = await running.status(.idle)
                    precondition(stillIdle.state == .idle)
                    let unrelatedValue = try await running.container.idle
                    precondition(unrelatedValue == 10)
                    let retried = try await running.retry(.a)
                    precondition(retried.isReady)
                    let current = await running.status(.a)
                    precondition(current.generation == 1 && current.state == .ready)
                    let retriedValue = try await running.container.a
                    precondition(retriedValue == 222)
                    await gate.releaseFirst()
                    // The original factory deliberately ignores cancellation.
                    // Its generated wrapper observes cancellation after return;
                    // this trace barrier confirms that late completion ran.
                    await cancellationTrace.waitForCancellation()
                    let afterLateCompletion = try await running.container.a
                    precondition(afterLateCompletion == 222)
                    let runningCopy = running
                    await runningCopy.close()
                    let sharedClose = await running.status(.a)
                    precondition(sharedClose.state == .closed)

                    let parent = try await Borrowing.makeOwned(input: 9)
                    let child = parent.container.child
                    await parent.close()
                    precondition(child.input == 9)
                }
            }
            """
        let file = directory.appendingPathComponent("Consumer.swift")
        try source.write(to: file, atomically: true, encoding: .utf8)
        let binary = directory.appendingPathComponent("Consumer")
        let compiled = try swift([
            "-parse-as-library", "-I", directory.path, "-L", directory.path, "-lInnoDI",
            "-Xlinker", "-rpath", "-Xlinker", directory.path, file.path, "-o", binary.path
        ])
        #expect(!compiled.timedOut, Comment(rawValue: compiled.combinedOutput))
        #expect(compiled.exitCode == 0, Comment(rawValue: compiled.combinedOutput))
        guard compiled.exitCode == 0, !compiled.timedOut else { return }
        let execution = Process()
        execution.executableURL = binary
        let result = try runCapturedProcess(execution, timeoutSeconds: 30)
        #expect(!result.timedOut, Comment(rawValue: result.combinedOutput))
        #expect(result.exitCode == 0, Comment(rawValue: result.combinedOutput))

        let unsafeCapture = try emitted("""
            @DIContainer(generateOwned: true) struct UnsafeCapture {
                @Input var local: LocalValue
                @Provide(.shared, initialization: .onDemand, factory: { (local: LocalValue) in local }) var lazy: LocalValue
                @Provide(.shared, asyncFactory: { (lazy: LocalValue) async in 1 }) var service: Int
            }
            """)
        let unsafeFile = directory.appendingPathComponent("UnsafeCapture.swift")
        try ("import InnoDI\nfinal class LocalValue {}\n" + unsafeCapture)
            .write(to: unsafeFile, atomically: true, encoding: .utf8)
        let rejectedCapture = try swift(["-typecheck", "-I", directory.path, unsafeFile.path])
        #expect(rejectedCapture.exitCode != 0)
        #expect(rejectedCapture.combinedOutput.contains("Sendable"), Comment(rawValue: rejectedCapture.combinedOutput))
        #expect(!rejectedCapture.combinedOutput.contains("Stack dump:"))

        let wrongToken = directory.appendingPathComponent("WrongToken.swift")
        try (source + """
            func invalid(_ owner: Chain._InnoDIOwner) async throws {
                try await owner.prepare(Isolated._InnoDIOwnedProvider.service)
            }
            """).write(to: wrongToken, atomically: true, encoding: .utf8)
        let rejectedToken = try swift(["-typecheck", "-parse-as-library", "-I", directory.path, wrongToken.path])
        #expect(rejectedToken.exitCode != 0)
        #expect(rejectedToken.combinedOutput.contains("cannot convert value of type"), Comment(rawValue: rejectedToken.combinedOutput))
        #expect(!rejectedToken.combinedOutput.contains("Stack dump:"))

        let wrongActor = directory.appendingPathComponent("WrongActor.swift")
        try (source + """
            nonisolated func invalid(_ owner: Isolated._InnoDIOwner) {
                _ = owner.container.lazy
            }
            """).write(to: wrongActor, atomically: true, encoding: .utf8)
        let rejectedActor = try swift(["-typecheck", "-parse-as-library", "-I", directory.path, wrongActor.path])
        #expect(rejectedActor.exitCode != 0)
        #expect(rejectedActor.combinedOutput.contains("main actor-isolated"), Comment(rawValue: rejectedActor.combinedOutput))
        #expect(!rejectedActor.combinedOutput.contains("Stack dump:"))
    }

    private func emitted(_ source: String, support: String = "") throws -> String {
        let syntax = Parser.parse(source: source)
        let declaration = try #require(syntax.statements.first?.item.as(StructDeclSyntax.self))
        let context = TestMacroExpansionContext()
        let model = try #require(DIContainerParser.parse(declaration: declaration, context: context))
        #expect(DIContainerValidator.validate(model: model, declaration: declaration, context: context))
        #expect(context.diagnostics.isEmpty)
        // These two explicitly owned-only fixtures cannot cover a convenience
        // that depends on the legacy Overrides declaration. The full-surface
        // fixtures and actual plugin cover that overload instead.
        let generated = try makeOwnedContainerDecls(model: model).filter { declaration in
            !((declaration.as(FunctionDeclSyntax.self)?.signature.parameterClause.parameters)
                .map { $0.contains { $0.secondName?.text == "_innoDIApplyOverrides" } } ?? false)
        }
        return "struct \(declaration.name.text) {\n\(support)\n\(generated.map { $0.formatted().description }.joined(separator: "\n"))\n}"
    }

    /// SwiftSyntax's expansion helper does not recursively expand an accessor
    /// attribute introduced by memberAttribute. Invoke the real peer/accessor
    /// roles explicitly against the original authored member, then compose the
    /// resulting AST with the real container generator; no storage is mocked.
    private func fullyEmitted(_ source: String, support: String = "") throws -> String {
        var syntax = Parser.parse(source: source)
        var declaration = try #require(syntax.statements.first?.item.as(StructDeclSyntax.self))
        if !support.isEmpty {
            let added = Parser.parse(source: support).statements.compactMap { $0.item.as(DeclSyntax.self) }
            let separated = added.map { declaration -> MemberBlockItemSyntax in
                var declaration = declaration
                declaration.leadingTrivia = .newlines(1) + declaration.leadingTrivia
                return MemberBlockItemSyntax(decl: declaration)
            }
            declaration.memberBlock.members = MemberBlockItemListSyntax(
                Array(declaration.memberBlock.members) + separated
            )
            syntax = Parser.parse(source: declaration.description)
            declaration = try #require(syntax.statements.first?.item.as(StructDeclSyntax.self))
        }
        let context = TestMacroExpansionContext()
        let model = try #require(DIContainerParser.parse(declaration: declaration, context: context))
        #expect(DIContainerValidator.validate(model: model, declaration: declaration, context: context))
        let containerAttribute = try #require(declaration.attributes.compactMap { $0.as(AttributeSyntax.self) }
            .first { ["DIContainer", "DIContainerRole"].contains($0.attributeName.trimmedDescription) })
        var attributed = declaration
        for index in declaration.memberBlock.members.indices {
            let member = declaration.memberBlock.members[index]
            guard var variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            let attributes = try DIContainerMacro.expansion(
                of: containerAttribute, attachedTo: declaration, providingAttributesFor: variable, in: context
            )
            variable.attributes = AttributeListSyntax(Array(variable.attributes) + attributes.map { .attribute($0) })
            attributed.memberBlock.members[index].decl = DeclSyntax(variable)
        }
        // Reparse only to restore parent ancestry after attaching the exact
        // attributes the compiler's memberAttribute phase supplies.
        let attributedSource = Parser.parse(source: attributed.description)
        let attributedContainer = try #require(attributedSource.statements.first?.item.as(StructDeclSyntax.self))
        let originalVariables = Dictionary(uniqueKeysWithValues: declaration.memberBlock.members.compactMap { member -> (String, VariableDeclSyntax)? in
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  let name = variable.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return nil }
            return (name, variable)
        })
        var members: [DeclSyntax] = []
        let macroNames: Set<String> = ["Input", "Provide", "SubContainer", "InnoDI._InnoDIProvideAccessor", "InnoDI._InnoDISubContainerAccessor"]
        for member in attributedContainer.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  let sourceAttribute = variable.attributes.compactMap({ $0.as(AttributeSyntax.self) })
                    .first(where: { ["Input", "Provide", "SubContainer"].contains($0.attributeName.trimmedDescription) }) else {
                members.append(member.decl)
                continue
            }
            let name = try #require(variable.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text)
            let original = try #require(originalVariables[name])
            let originalAttribute = try #require(original.attributes.compactMap { $0.as(AttributeSyntax.self) }
                .first { ["Input", "Provide", "SubContainer"].contains($0.attributeName.trimmedDescription) })
            // Match the real compiler: attached roles receive the original
            // member and its original lexical parent. Generated member
            // attributes affect the final declaration; reparsing them as user-
            // authored attributes would incorrectly invoke closed shape rules.
            let isChild = sourceAttribute.attributeName.trimmedDescription == "SubContainer"
            let supportName = isChild ? "InnoDI._InnoDISubContainerAccessor" : "InnoDI._InnoDIProvideAccessor"
            let attribute = try #require(variable.attributes.compactMap { $0.as(AttributeSyntax.self) }
                .first { $0.attributeName.trimmedDescription == supportName })
            let peers: [DeclSyntax]
            let accessors: [AccessorDeclSyntax]
            if isChild {
                _ = try SubContainerMacro.expansion(of: originalAttribute, providingPeersOf: original, in: context)
                peers = try InnoDISubContainerAccessorMacro.expansion(of: attribute, providingPeersOf: original, in: context)
                accessors = try InnoDISubContainerAccessorMacro.expansion(of: attribute, providingAccessorsOf: original, in: context)
            } else {
                let publicPeers = try ProvideMacro.expansion(of: originalAttribute, providingPeersOf: original, in: context)
                peers = publicPeers + (try InnoDIProvideAccessorMacro.expansion(of: attribute, providingPeersOf: original, in: context))
                accessors = try InnoDIProvideAccessorMacro.expansion(of: attribute, providingAccessorsOf: original, in: context)
            }
            let roleEvidence = "Attributed source:\n\(attributedSource.description)\nDiagnostics:\n\(context.diagnostics.map(\.message).joined(separator: "\n"))"
            try #require(!peers.isEmpty, Comment(rawValue: "Missing peers for \(variable.trimmedDescription).\n\(roleEvidence)"))
            try #require(!accessors.isEmpty, Comment(rawValue: "Missing accessors for \(variable.trimmedDescription).\n\(roleEvidence)"))
            var property = variable
            property.attributes = variable.attributes.filter {
                guard let attribute = $0.as(AttributeSyntax.self) else { return true }
                return !macroNames.contains(attribute.attributeName.trimmedDescription)
            }
            var binding = try #require(property.bindings.first)
            binding.initializer = nil
            binding.accessorBlock = AccessorBlockSyntax(accessors: .accessors(AccessorDeclListSyntax(accessors)))
            property.bindings = PatternBindingListSyntax([binding])
            members.append(DeclSyntax(property))
            members.append(contentsOf: peers)
        }
        members.append(contentsOf: try DIContainerCodeGenerator.generateAll(for: model))
        #expect(context.diagnostics.isEmpty)
        var result = declaration
        result.attributes = declaration.attributes.filter {
            guard let attribute = $0.as(AttributeSyntax.self) else { return true }
            return !["DIContainer", "DIContainerRole"].contains(attribute.attributeName.trimmedDescription)
        }
        result.memberBlock.members = MemberBlockItemListSyntax(members.map { MemberBlockItemSyntax(decl: $0) })
        return result.formatted().description
    }

    private func swift(_ arguments: [String]) throws -> CapturedProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swiftc", "-swift-version", "6", "-strict-concurrency=complete", "-warnings-as-errors"] + arguments
        return try runCapturedProcess(process, timeoutSeconds: 90)
    }
}
