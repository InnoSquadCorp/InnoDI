import InnoDI
import Testing

private final class DetachedCompositionItem {}

private struct DetachedCompositionHandles {
    let shared: InnoDI.Lazy<DetachedCompositionItem>
    let fresh: InnoDI.Provider<DetachedCompositionItem>
}

@DIContainer
fileprivate struct DetachedCompositionContainer {
    @Provide(.shared, factory: DetachedCompositionItem())
    var shared: DetachedCompositionItem
    @Provide(.transient, factory: DetachedCompositionItem())
    var fresh: DetachedCompositionItem
    @Multibinding([\Self.shared, \Self.fresh])
    var items: [DetachedCompositionItem]
    @Provide(.shared, factory: { (items: InnoDI.Provider<[DetachedCompositionItem]>) in items })
    var collection: InnoDI.Provider<[DetachedCompositionItem]>
    @Provide(.transient, factory: {
        (shared: InnoDI.Lazy<DetachedCompositionItem>, fresh: InnoDI.Provider<DetachedCompositionItem>) in
        DetachedCompositionHandles(shared: shared, fresh: fresh)
    })
    var handles: DetachedCompositionHandles
    @Provide(.shared, factory: { (handles: InnoDI.Provider<DetachedCompositionHandles>) in handles })
    var nested: InnoDI.Provider<DetachedCompositionHandles>
}

@Suite("Detached deferred composition")
struct DetachedCompositionRuntimeTests {
    @Test("Provider of multibinding preserves order, lifetimes and collection overrides")
    func collectionSemantics() {
        let container = DetachedCompositionContainer()
        let first = container.collection()
        let second = container.collection()
        #expect(first.count == 2)
        #expect(second.count == 2)
        #expect(first[0] === container.shared)
        #expect(first[0] === second[0])
        #expect(first[1] !== second[1])
        let replacement = DetachedCompositionItem()
        let overridden = DetachedCompositionContainer(items: [replacement])
        #expect(overridden.collection().count == 1)
        #expect(overridden.collection()[0] === replacement)
    }

    @Test("Escaped nested handles preserve identities and release shared context with the last handle")
    func nestedSemanticsAndLifetime() {
        weak var weakShared: DetachedCompositionItem?
        var escaped: DetachedCompositionHandles?
        do {
            let container = DetachedCompositionContainer()
            weakShared = container.shared
            escaped = container.nested()
            #expect(escaped?.shared() === container.shared)
            #expect(escaped?.fresh() !== escaped?.fresh())
        }
        #expect(weakShared != nil)
        #expect(escaped?.shared() === weakShared)
        escaped = nil
        #expect(weakShared == nil)
    }
}
