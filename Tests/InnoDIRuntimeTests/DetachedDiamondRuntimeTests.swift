import InnoDI
import Testing

@MainActor
private final class DiamondLifetimeProbe {
    var leafCreations = 0
}

@DIContainerRole(role: ContainerRole.local, mainActor: true)
fileprivate struct DetachedDiamondContainer {
    @Input var probe: DiamondLifetimeProbe
    @Provide(.transient, factory: { (probe: DiamondLifetimeProbe) in probe.leafCreations += 1; return 1 })
    var a0: Int
    @Provide(.transient, factory: { (probe: DiamondLifetimeProbe) in probe.leafCreations += 1; return 2 })
    var b0: Int
    @Provide(.transient, factory: { (a0: Int, b0: Int) in a0 + b0 })
    var a1: Int
    @Provide(.transient, factory: { (a0: Int, b0: Int) in a0 + b0 })
    var b1: Int
    @Provide(.transient, factory: { (a1: Int, b1: Int) in a1 + b1 })
    var a2: Int
    @Provide(.transient, factory: { (a1: Int, b1: Int) in a1 + b1 })
    var b2: Int
    @Provide(.transient, factory: { (a2: Int, b2: Int) in a2 + b2 })
    var a3: Int
    @Provide(.transient, factory: { (a2: Int, b2: Int) in a2 + b2 })
    var b3: Int
    @Provide(.transient, factory: { (a3: Int, b3: Int) in a3 + b3 })
    var a4: Int
    @Provide(.transient, factory: { (a3: Int, b3: Int) in a3 + b3 })
    var b4: Int
    @Provide(.transient, factory: { (a4: Int, b4: Int) in a4 + b4 })
    var a5: Int
    @Provide(.transient, factory: { (a4: Int, b4: Int) in a4 + b4 })
    var b5: Int
    @Provide(.transient, factory: { (a5: Int, b5: Int) in a5 + b5 })
    var a6: Int
    @Provide(.transient, factory: { (a5: Int, b5: Int) in a5 + b5 })
    var b6: Int
    @Provide(.transient, factory: { (a6: Int, b6: Int) in a6 + b6 })
    var a7: Int
    @Provide(.transient, factory: { (a6: Int, b6: Int) in a6 + b6 })
    var b7: Int
    @Provide(.transient, factory: { (a7: Int, b7: Int) in a7 + b7 })
    var a8: Int
    @Provide(.transient, factory: { (a7: Int, b7: Int) in a7 + b7 })
    var b8: Int
    @Provide(.transient, factory: { (a8: Int, b8: Int) in a8 + b8 })
    var a9: Int
    @Provide(.transient, factory: { (a8: Int, b8: Int) in a8 + b8 })
    var b9: Int
    @Provide(.transient, factory: { (a9: Int, b9: Int) in a9 + b9 })
    var a10: Int
    @Provide(.transient, factory: { (a9: Int, b9: Int) in a9 + b9 })
    var b10: Int
    @Provide(.transient, factory: { (a10: Int, b10: Int) in a10 + b10 })
    var a11: Int
    @Provide(.transient, factory: { (a10: Int, b10: Int) in a10 + b10 })
    var b11: Int
    @Provide(.transient, factory: { (a11: Int, b11: Int) in a11 + b11 })
    var a12: Int
    @Provide(.transient, factory: { (a11: Int, b11: Int) in a11 + b11 })
    var b12: Int
    @Provide(.shared, factory: { (a12: InnoDI.Provider<Int>) in a12 })
    var root: InnoDI.Provider<Int>
}

@Suite("Detached transient diamond contracts")
@MainActor
struct DetachedDiamondRuntimeTests {
    @Test("Code sharing preserves per-edge transient creation, copies and overrides")
    func transientSemantics() {
        let probe = DiamondLifetimeProbe()
        let container = DetachedDiamondContainer(probe: probe)
        #expect(probe.leafCreations == 0)
        #expect(container.root() == 6_144)
        #expect(probe.leafCreations == 4_096)
        let copy = container
        #expect(copy.root() == 6_144)
        #expect(probe.leafCreations == 8_192)

        let overridden = DetachedDiamondContainer(probe: probe, a1: 900)
        #expect(overridden.root() == 924_672)
        #expect(probe.leafCreations == 10_240)

        let rootOverride = DetachedDiamondContainer(probe: probe, root: InnoDI.Provider { 42 })
        #expect(rootOverride.root() == 42)
        #expect(probe.leafCreations == 10_240)
    }

    @Test("Deep shared resolver code releases its dependency context with the final handle")
    func detachedLifetime() {
        weak var weakProbe: DiamondLifetimeProbe?
        var handle: InnoDI.Provider<Int>?
        do {
            let probe = DiamondLifetimeProbe()
            weakProbe = probe
            let container = DetachedDiamondContainer(probe: probe)
            handle = container.root
        }
        #expect(weakProbe != nil)
        #expect(handle?() == 6_144)
        handle = nil
        #expect(weakProbe == nil)
    }
}
