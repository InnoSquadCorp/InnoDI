import Testing

import InnoDI

// Smoke fixtures kept minimal — proper sub-container runtime coverage lives
// in `SubContainerRuntimeTests.swift`. This file gates the basic codegen
// happy paths so we catch macro expansion breakage before validator / CLI /
// docs land.

struct SubSmokeConfig: Equatable {
    let endpoint: String
}

@DIContainer
struct SubSmokeFeatureContainer {
    @Provide(.input) var config: SubSmokeConfig

    @Provide(.shared, factory: SubSmokeStore())
    var store: SubSmokeStore
}

final class SubSmokeStore { init() {} }

final class SubOnlyStore {
    let label: String

    init(label: String) {
        self.label = label
    }
}

@DIContainer
struct SubSmokeAppContainer {
    @Provide(.input) var config: SubSmokeConfig

    @SubContainer(scope: .shared)
    var feature: SubSmokeFeatureContainer
}

@DIContainer
struct SubSmokeAppContainerTransient {
    @Provide(.input) var config: SubSmokeConfig

    @SubContainer(scope: .transient)
    var feature: SubSmokeFeatureContainer
}

@DIContainer
struct SubOnlyFeatureContainer {
    @Provide(.shared, factory: SubOnlyStore(label: "default"))
    var store: SubOnlyStore
}

@DIContainer
struct SubOnlyParentContainer {
    @SubContainer(scope: .shared)
    var child: SubOnlyFeatureContainer
}

@Suite("SubContainer smoke")
struct SubContainerSmokeTests {
    @Test("`.shared` sub-container caches across reads")
    func sharedCaches() {
        let app = SubSmokeAppContainer(config: SubSmokeConfig(endpoint: "x"))
        let first = app.feature
        let second = app.feature
        #expect(first.config == SubSmokeConfig(endpoint: "x"))
        // Struct value-type identity — both reads return the same cached storage.
        #expect(first.store === second.store)
    }

    @Test("`.transient` sub-container builds fresh on every read")
    func transientFresh() {
        let app = SubSmokeAppContainerTransient(config: SubSmokeConfig(endpoint: "y"))
        let first = app.feature
        let second = app.feature
        #expect(first.config == SubSmokeConfig(endpoint: "y"))
        // Each read produces a freshly-constructed `.shared` store inside the
        // newly-built child container.
        #expect(first.store !== second.store)
    }

    @Test("Sub-container-only parent synthesizes an init with no input parameters")
    func subContainerOnlyParentInitializes() {
        let parent = SubOnlyParentContainer()
        #expect(parent.child.store.label == "default")
        #expect(parent.child.store === parent.child.store)
    }

    @Test("Sub-container-only parent synthesizes withOverrides without input parameters")
    func subContainerOnlyParentWithOverrides() {
        let label = SubOnlyParentContainer.withOverrides { overrides in
            overrides.childOverrides = { childOverrides in
                childOverrides.store = SubOnlyStore(label: "override")
            }
        } operation: { parent in
            parent.child.store.label
        }

        #expect(label == "override")
    }
}
