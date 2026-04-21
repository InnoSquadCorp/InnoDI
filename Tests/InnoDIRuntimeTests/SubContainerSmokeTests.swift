import Testing

import InnoDI

// Smoke fixtures kept minimal — proper Phase M runtime coverage lives in
// `SubContainerRuntimeTests.swift` (M-7). This file gates the M-4 codegen
// against the most basic happy paths so we catch macro expansion breakage
// before validator / CLI / docs land.

struct SubSmokeConfig: Equatable {
    let endpoint: String
}

@DIContainer
struct SubSmokeFeatureContainer {
    @Provide(.input) var config: SubSmokeConfig

    @Provide(.shared, factory: SubSmokeStore(), concrete: true)
    var store: SubSmokeStore
}

final class SubSmokeStore { init() {} }

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
}
