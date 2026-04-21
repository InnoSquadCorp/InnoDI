import Testing

import InnoDI

// MARK: - Fixtures
//
// The Phase M runtime tests cover four shapes the user can write:
//
// 1. `.shared` sub-container with auto-matched parent inputs,
// 2. `.transient` sub-container with auto-matched parent inputs,
// 3. `with: [\.parentMember]` keypath remapping (single-parent subset),
// 4. parent override builder threading full replacement +
//    `<name>Overrides` chain into the child's own convenience init.

struct RuntimeParentConfig: Equatable {
    let endpoint: String
}

final class RuntimeChildStore { init() {} }
final class RuntimeSubsetStore { init() {} }

@DIContainer
struct RuntimeChildContainer {
    @Provide(.input) var config: RuntimeParentConfig

    @Provide(.shared, factory: RuntimeChildStore(), concrete: true)
    var store: RuntimeChildStore
}

@DIContainer
struct RuntimeParentSharedContainer {
    @Provide(.input) var config: RuntimeParentConfig

    @SubContainer(scope: .shared)
    var child: RuntimeChildContainer
}

@DIContainer
struct RuntimeParentTransientContainer {
    @Provide(.input) var config: RuntimeParentConfig

    @SubContainer(scope: .transient)
    var child: RuntimeChildContainer
}

@DIContainer
struct RuntimeSubsetChildContainer {
    @Provide(.input) var config: RuntimeParentConfig

    @Provide(.shared, factory: RuntimeSubsetStore(), concrete: true)
    var store: RuntimeSubsetStore
}

@DIContainer
struct RuntimeParentWithSubsetContainer {
    @Provide(.input) var config: RuntimeParentConfig
    @Provide(.input) var extra: String

    @SubContainer(scope: .shared, with: [\RuntimeParentWithSubsetContainer.config])
    var child: RuntimeSubsetChildContainer
}

@DIContainer
struct RuntimeBindingsChildContainer {
    @Provide(.input) var featureConfig: RuntimeParentConfig
}

@DIContainer
struct RuntimeParentWithBindingsContainer {
    @Provide(.input) var config: RuntimeParentConfig

    @SubContainer(
        scope: .shared,
        bindings: [(child: \RuntimeBindingsChildContainer.featureConfig, parent: \RuntimeParentWithBindingsContainer.config)]
    )
    var child: RuntimeBindingsChildContainer
}

@DIContainer
struct RuntimeParentWithTransientBindingsContainer {
    @Provide(.input) var config: RuntimeParentConfig

    @SubContainer(
        scope: .transient,
        bindings: [(child: \RuntimeBindingsChildContainer.featureConfig, parent: \RuntimeParentWithTransientBindingsContainer.config)]
    )
    var child: RuntimeBindingsChildContainer
}

@DIContainer
struct RuntimeInputOnlyChildContainer {
    @Provide(.input) var config: RuntimeParentConfig
}

@DIContainer
struct RuntimeParentWithInputOnlyChildContainer {
    @Provide(.input) var config: RuntimeParentConfig

    @SubContainer(scope: .shared)
    var child: RuntimeInputOnlyChildContainer
}

// Override tests need deterministic mock identity so reference comparisons
// read naturally.

final class OverrideChildStore {
    let tag: String
    init(tag: String) { self.tag = tag }
}

@DIContainer
struct OverrideCapableChild {
    @Provide(.input) var config: RuntimeParentConfig

    @Provide(.shared, factory: OverrideChildStore(tag: "default"), concrete: true)
    var store: OverrideChildStore
}

@DIContainer
struct OverrideParentContainer {
    @Provide(.input) var config: RuntimeParentConfig

    @SubContainer(scope: .shared)
    var feature: OverrideCapableChild
}

@DIContainer
struct OverrideTransientBindingsChild {
    @Provide(.input) var featureConfig: RuntimeParentConfig

    @Provide(.shared, factory: OverrideChildStore(tag: "default"), concrete: true)
    var store: OverrideChildStore
}

@DIContainer
struct OverrideTransientBindingsParentContainer {
    @Provide(.input) var config: RuntimeParentConfig

    @SubContainer(
        scope: .transient,
        bindings: [(child: \OverrideTransientBindingsChild.featureConfig, parent: \OverrideTransientBindingsParentContainer.config)]
    )
    var feature: OverrideTransientBindingsChild
}

@Suite("SubContainer runtime (Phase M)")
struct SubContainerRuntimeTests {
    // MARK: - Scope behaviour

    @Test("`.shared` sub-container caches across accessor reads")
    func sharedSubContainerCaches() {
        let parent = RuntimeParentSharedContainer(config: RuntimeParentConfig(endpoint: "x"))
        // Value-type equality doesn't help here — the parent's
        // `_storage_sub_child` holds one child, and both accesses return
        // the same struct copy, so their inner `.shared` store references
        // are identical.
        #expect(parent.child.store === parent.child.store)
    }

    @Test("`.transient` sub-container returns a fresh instance every read")
    func transientSubContainerFresh() {
        let parent = RuntimeParentTransientContainer(config: RuntimeParentConfig(endpoint: "y"))
        let first = parent.child
        let second = parent.child
        // Each accessor invocation runs `_innoDISubBuild_child`, which
        // rebuilds the whole child, including a new `.shared` store.
        #expect(first.store !== second.store)
    }

    // MARK: - Input propagation

    @Test("Parent `.input` flows into the child automatically by name")
    func inputPropagatesByName() {
        let parent = RuntimeParentSharedContainer(config: RuntimeParentConfig(endpoint: "propagate"))
        #expect(parent.child.config == RuntimeParentConfig(endpoint: "propagate"))
    }

    @Test("with: subset forwards only the selected parent inputs")
    func withRestrictsForwardedInputs() {
        let parent = RuntimeParentWithSubsetContainer(
            config: RuntimeParentConfig(endpoint: "subset"),
            extra: "ignored"
        )
        // Compile-time proof of the subset wiring: `RuntimeSubsetChildContainer`
        // only accepts `config`, so this fixture would fail to compile if the
        // generated child init forwarded `extra` as well.
        #expect(parent.child.config == RuntimeParentConfig(endpoint: "subset"))
    }

    @Test("bindings: remaps parent and child labels explicitly")
    func bindingsRemapParentAndChildLabels() {
        let parent = RuntimeParentWithBindingsContainer(
            config: RuntimeParentConfig(endpoint: "bindings")
        )
        #expect(parent.child.featureConfig == RuntimeParentConfig(endpoint: "bindings"))
    }

    @Test("`.transient` bindings: remap parent and child labels explicitly")
    func transientBindingsRemapParentAndChildLabels() {
        let parent = RuntimeParentWithTransientBindingsContainer(
            config: RuntimeParentConfig(endpoint: "transient-bindings")
        )
        #expect(parent.child.featureConfig == RuntimeParentConfig(endpoint: "transient-bindings"))
    }

    // MARK: - Overrides builder integration

    @Test("Overrides.feature fully replaces the child container")
    func overrideReplacesChildEntirely() {
        let mockChild = OverrideCapableChild(
            config: RuntimeParentConfig(endpoint: "mock"),
            store: OverrideChildStore(tag: "injected")
        )
        let parent = OverrideParentContainer(config: RuntimeParentConfig(endpoint: "ignored")) {
            $0.feature = mockChild
        }
        #expect(parent.feature.store.tag == "injected")
    }

    @Test("Overrides.featureOverrides threads into the child's own Overrides")
    func overrideChainAppliesToChildConvenienceInit() {
        let parent = OverrideParentContainer(config: RuntimeParentConfig(endpoint: "chain")) {
            $0.featureOverrides = { childOv in
                childOv.store = OverrideChildStore(tag: "chained")
            }
        }
        #expect(parent.feature.store.tag == "chained")
        // Parent's `.input` still flows through — the child override block
        // only replaces the shared members it mentions.
        #expect(parent.feature.config == RuntimeParentConfig(endpoint: "chain"))
    }

    @Test("Direct replacement wins over the chain closure when both are set")
    func directReplacementWinsOverChain() {
        let mockChild = OverrideCapableChild(
            config: RuntimeParentConfig(endpoint: "mock"),
            store: OverrideChildStore(tag: "direct-wins")
        )
        let parent = OverrideParentContainer(config: RuntimeParentConfig(endpoint: "ignored")) {
            $0.feature = mockChild
            $0.featureOverrides = { childOv in
                // This block is dropped because the direct replacement
                // takes precedence in the init's `if let direct = ...`
                // branch.
                childOv.store = OverrideChildStore(tag: "chain-should-not-win")
            }
        }
        #expect(parent.feature.store.tag == "direct-wins")
    }

    @Test("withOverrides threads chain-style child overrides scoped to an operation")
    func withOverridesScopedChildChain() {
        let tag = OverrideParentContainer.withOverrides(
            config: RuntimeParentConfig(endpoint: "scoped")
        ) { overrides in
            overrides.featureOverrides = { childOv in
                childOv.store = OverrideChildStore(tag: "scoped-override")
            }
        } operation: { container in
            container.feature.store.tag
        }
        #expect(tag == "scoped-override")
    }

    @Test("Remapped transient child overrides still apply to the child convenience init")
    func transientBindingsOverrideChainUsesRemappedInputs() {
        let parent = OverrideTransientBindingsParentContainer(
            config: RuntimeParentConfig(endpoint: "transient-override")
        ) {
            $0.featureOverrides = { childOv in
                childOv.store = OverrideChildStore(tag: "transient-chain")
            }
        }
        let child = parent.feature
        #expect(child.featureConfig == RuntimeParentConfig(endpoint: "transient-override"))
        #expect(child.store.tag == "transient-chain")
    }

    @Test("Direct replacement still wins over childOverrides for remapped transient children")
    func transientBindingsDirectReplacementWinsOverChain() {
        let replacement = OverrideTransientBindingsChild(
            featureConfig: RuntimeParentConfig(endpoint: "replacement"),
            store: OverrideChildStore(tag: "transient-direct")
        )
        let parent = OverrideTransientBindingsParentContainer(
            config: RuntimeParentConfig(endpoint: "ignored")
        ) {
            $0.feature = replacement
            $0.featureOverrides = { childOv in
                childOv.store = OverrideChildStore(tag: "transient-chain-should-not-win")
            }
        }

        let child = parent.feature
        #expect(child.featureConfig == RuntimeParentConfig(endpoint: "replacement"))
        #expect(child.store.tag == "transient-direct")
    }

    @Test("input-only child sub-containers still support direct replacement")
    func inputOnlyChildDirectReplacementStillWorks() {
        let replacement = RuntimeInputOnlyChildContainer(
            config: RuntimeParentConfig(endpoint: "replacement")
        )
        let parent = RuntimeParentWithInputOnlyChildContainer(
            config: RuntimeParentConfig(endpoint: "ignored")
        ) {
            $0.child = replacement
        }
        #expect(parent.child.config == RuntimeParentConfig(endpoint: "replacement"))
    }

    @Test("input-only child featureOverrides closures compile and execute as no-ops")
    func inputOnlyChildOverrideClosureCompilesAndExecutes() {
        var didApply = false
        let parent = RuntimeParentWithInputOnlyChildContainer(
            config: RuntimeParentConfig(endpoint: "input-only")
        ) {
            $0.childOverrides = { _ in
                didApply = true
            }
        }
        #expect(didApply)
        #expect(parent.child.config == RuntimeParentConfig(endpoint: "input-only"))
    }
}
