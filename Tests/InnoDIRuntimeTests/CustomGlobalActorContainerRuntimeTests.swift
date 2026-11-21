import Testing

import InnoDI

// A source-written custom global actor isolates every generated container
// member. These fixtures compile only while the generated async
// `withOverrides` overloads inherit that isolation instead of overriding it
// with `nonisolated(nonsending)`, and while a nested `@AssistedFactory`
// receives the container's actor.

@globalActor
actor CustomContainerTestActor {
    static let shared = CustomContainerTestActor()
}

final class CustomActorReadCounter {
    var reads = 0
}

/// Callable without `await` only from code isolated to the custom actor, so
/// a factory that calls it proves the generated initializer runs there.
@CustomContainerTestActor
func markCustomActorRead(_ counter: CustomActorReadCounter) -> Int {
    counter.reads += 1
    return counter.reads
}

@CustomContainerTestActor
@DIContainer
struct CustomActorInputOnlyContainer {
    @Input var seed: Int
}

@CustomContainerTestActor
@DIContainer
struct CustomActorSyncProviderContainer {
    @Input var seed: Int
    @Input var counter: CustomActorReadCounter

    @Provide(.shared, factory: { (seed: Int) in seed * 2 })
    var doubled: Int

    @Provide(.shared, factory: { (counter: CustomActorReadCounter) in markCustomActorRead(counter) })
    var marked: Int

    @Provide(.transient, factory: { (seed: Int) in seed + 1 })
    var fresh: Int

    @Provide(.shared, initialization: .onDemand, factory: { (seed: Int) in seed + 3 })
    var onDemand: Int
}

@CustomContainerTestActor
@DIContainer
struct CustomActorEagerAsyncContainer {
    @Input var seed: Int

    @Provide(.shared, asyncFactory: { (seed: Int) async in seed + 10 })
    var eager: Int
}

@CustomContainerTestActor
@DIContainer
struct CustomActorAsyncOnDemandContainer {
    @Input var seed: Int

    @Provide(.shared, initialization: .onDemand, asyncFactory: { (seed: Int) async in seed + 20 })
    var lazyValue: Int
}

@CustomContainerTestActor
@DIContainer
struct CustomActorDeferredContainer {
    @Input var seed: Int

    @Provide(.transient, factory: { (seed: Int) in seed + 1 })
    var fresh: Int

    @Provide(.shared, factory: { (fresh: InnoDI.Provider<Int>) in fresh })
    var freshProvider: InnoDI.Provider<Int>

    @Provide(.shared, factory: { (fresh: InnoDI.Lazy<Int>) in fresh })
    var freshLazy: InnoDI.Lazy<Int>
}

@CustomContainerTestActor
@DIContainer
struct CustomActorChildContainer {
    @Input var seed: Int
}

@DIContainer
struct CustomActorPlainChildContainer {
    @Input var seed: Int
}

@CustomContainerTestActor
@DIContainerRole(role: ContainerRole.root)
struct CustomActorParentContainer {
    @Input var seed: Int

    @SubContainer(scope: .shared, with: [\Self.seed])
    var sharedChild: CustomActorChildContainer

    @SubContainer(scope: .transient, with: [\Self.seed])
    var transientChild: CustomActorChildContainer

    @SubContainer(scope: .shared, with: [\Self.seed])
    var plainChild: CustomActorPlainChildContainer
}

@CustomContainerTestActor
@DIContainer
struct CustomActorAssistedContainer {
    @Input var seed: Int
    @Input(.assisted) var request: Int

    @Provide(.shared, factory: { (seed: Int, request: Int) in seed + request })
    var value: Int

    @AssistedFactory(
        CustomActorAssistedContainer.self,
        static: [\CustomActorAssistedContainer.seed],
        assisted: [\CustomActorAssistedContainer.request]
    )
    struct AssistedFactory {}
}

@CustomContainerTestActor
@DIContainer
struct CustomActorFactoryParentContainer {
    @Input var seed: Int

    @Provide(.shared, effect: .sideEffect, factory: { (seed: Int) in seed * 100 })
    var audited: Int

    @SubContainerFactory(
        CustomActorAssistedContainer.self,
        bindings: [(child: \CustomActorAssistedContainer.seed, parent: \Self.seed)]
    )
    var session: CustomActorAssistedContainer.AssistedFactory
}

@Suite("Custom global actor containers")
struct CustomGlobalActorContainerRuntimeTests {
    @CustomContainerTestActor
    @Test("Every generated shape compiles and runs on the container's actor")
    func shapesRunOnTheCustomActor() async throws {
        let counter = CustomActorReadCounter()
        let sync = CustomActorSyncProviderContainer(seed: 2, counter: counter)
        #expect(sync.doubled == 4)
        #expect(sync.marked == 1)
        #expect(counter.reads == 1)
        #expect(sync.fresh == 3)
        sync.prewarm(.onDemand)
        #expect(sync.onDemand == 5)

        #expect(await CustomActorEagerAsyncContainer(seed: 1).eager == 11)

        let onDemand = CustomActorAsyncOnDemandContainer(seed: 1)
        #expect(try await onDemand.lazyValue == 21)
        await onDemand.closeAsyncProviders()

        let deferred = CustomActorDeferredContainer(seed: 4)
        #expect(deferred.freshProvider() == 5)
        #expect(deferred.freshLazy() == 5)

        let parent = CustomActorParentContainer(seed: 7)
        #expect(parent.sharedChild.seed == 7)
        #expect(parent.transientChild.seed == 7)
        #expect(parent.plainChild.seed == 7)

        let factory = CustomActorAssistedContainer.AssistedFactory(seed: 1)
        #expect(factory(request: 2).value == 3)
        #expect(factory(request: 2) { $0.value = 9 }.value == 9)

        let factoryParent = CustomActorFactoryParentContainer(seed: 4) { $0.audited = 1 }
        #expect(factoryParent.audited == 1)
        #expect(factoryParent.session(request: 5).value == 9)
        #expect(CustomActorFactoryParentContainer.Overrides().missingEffectOverrides.count == 1)
    }

    @CustomContainerTestActor
    @Test("All four withOverrides overloads run on the actor from an isolated caller")
    func withOverridesFromIsolatedCaller() async throws {
        let sync = CustomActorInputOnlyContainer.withOverrides(seed: 1) { _ in } operation: { container in
            container.seed
        }
        let syncThrows = try CustomActorInputOnlyContainer.withOverrides(seed: 2) { _ in } operation: { container throws in
            container.seed
        }
        let async = await CustomActorInputOnlyContainer.withOverrides(seed: 3) { _ in } operation: { container async in
            CustomContainerTestActor.shared.preconditionIsolated()
            return container.seed
        }
        let asyncThrows = try await CustomActorAsyncOnDemandContainer.withOverrides(seed: 1) { _ in } operation: { container async throws in
            CustomContainerTestActor.shared.preconditionIsolated()
            return try await container.lazyValue
        }
        #expect([sync, syncThrows, async, asyncThrows] == [1, 2, 3, 21])
    }

    @Test("Async withOverrides hops a nonisolated caller onto the actor")
    func asyncWithOverridesFromNonisolatedCaller() async throws {
        let doubled = await CustomActorSyncProviderContainer.withOverrides(
            seed: 5,
            counter: CustomActorReadCounter()
        ) { overrides in
            overrides.doubled = 100
        } operation: { container async in
            CustomContainerTestActor.shared.preconditionIsolated()
            return await container.doubled
        }
        #expect(doubled == 100)

        let childSeed = try await CustomActorParentContainer.withOverrides(seed: 6) { _ in } operation: { container async throws in
            CustomContainerTestActor.shared.preconditionIsolated()
            return await container.transientChild.seed
        }
        #expect(childSeed == 6)
    }
}
