import InnoDI
import Testing

// Deliberately non-Sendable: selection tokens must never transport values or
// require a value's conformance merely to choose it for synchronous prewarming.
fileprivate final class TypedPrewarmValue {}

@MainActor
fileprivate final class TypedPrewarmLog {
    var events: [String] = []
    func make(_ name: String) -> TypedPrewarmValue {
        events.append(name)
        return TypedPrewarmValue()
    }
}

@DIContainerRole(role: ContainerRole.local, mainActor: true)
fileprivate struct TypedPrewarmContainer {
    @Input var log: TypedPrewarmLog
    @Provide(.shared, initialization: .onDemand, factory: { (log: TypedPrewarmLog) in
        log.make("first")
    }) var first: TypedPrewarmValue
    @Provide(.shared, initialization: .onDemand, factory: { (log: TypedPrewarmLog) in
        log.make("second")
    }) var second: TypedPrewarmValue
    @Provide(.shared, initialization: .onDemand, factory: { (log: TypedPrewarmLog) in
        log.make("unused")
    }) var unused: TypedPrewarmValue
}

@DIContainer
fileprivate struct TypedPrewarmCallerIsolatedContainer {
    @Input var PrewarmProvider: Int
    @Provide(.shared, initialization: .onDemand, factory: TypedPrewarmValue())
    var value: TypedPrewarmValue
}

@Suite("Typed synchronous prewarming")
struct TypedPrewarmRuntimeTests {
    @MainActor
    @Test("Selections run in argument order, repeats reuse caches, and unselected values stay lazy")
    func selectedOrderCachingAndLaziness() {
        let log = TypedPrewarmLog()
        let container = TypedPrewarmContainer(log: log)
        #expect(log.events.isEmpty)

        container.prewarm(.second, .first, .second)
        #expect(log.events == ["second", "first"])
        let copy = container
        copy.prewarm(.first, .second)
        #expect(copy.first === container.first)
        #expect(copy.second === container.second)
        #expect(log.events == ["second", "first"])

        container.prewarm(.unused)
        #expect(log.events == ["second", "first", "unused"])
    }

    @MainActor
    @Test("Overridden values prewarm without constructing a factory")
    func overrideIdentity() {
        let log = TypedPrewarmLog()
        let replacement = TypedPrewarmValue()
        let container = TypedPrewarmContainer(log: log, first: replacement)
        container.prewarm(.first, .first)
        #expect(log.events.isEmpty)
        #expect(container.first === replacement)
    }

    @MainActor
    @Test("Empty selections are a nonthrowing no-op")
    func emptySelection() {
        let log = TypedPrewarmLog()
        let container = TypedPrewarmContainer(log: log)
        container.prewarm()
        #expect(log.events.isEmpty)
        container.prewarm(.second)
        container.prewarm(.first)
        #expect(log.events == ["second", "first"])
    }

    @MainActor
    @Test("Sendable selections cross executors while non-Sendable services stay isolated")
    func selectionIsSendable() async {
        let selection = await Task.detached {
            TypedPrewarmContainer._InnoDIPrewarmProvider.second
        }.value
        let log = TypedPrewarmLog()
        let container = TypedPrewarmContainer(log: log)
        container.prewarm(selection)
        #expect(log.events == ["second"])
    }

    @Test("Ordinary synchronous containers keep non-Sendable values on the caller")
    func callerIsolatedValuesAndSameSpelledInput() throws {
        let container = TypedPrewarmCallerIsolatedContainer(PrewarmProvider: 7)
        container.prewarm(.value)
        let value = container.value
        container.prewarm()
        container.prewarm(.value)
        #expect(value === container.value)
        #expect(container.PrewarmProvider == 7)
    }
}
