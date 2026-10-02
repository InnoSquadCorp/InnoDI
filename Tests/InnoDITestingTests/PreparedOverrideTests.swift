import InnoDITesting
import Testing

final class PreparedOverrideCounter {
    private(set) var count = 0

    func make() -> Int {
        count += 1
        return -1
    }
}

final class PreparedOverrideReference: Sendable {}
final class PreparedActorLocalValue {}

@DIContainer(generateOwned: true)
struct PreparedEffectServices {
    @Input var counter: PreparedOverrideCounter
    @Provide(.shared, effect: .sideEffect, factory: { (counter: PreparedOverrideCounter) in counter.make() })
    var marked: Int
    @Provide(.shared, asyncFactory: { (marked: Int) async in marked + 1 })
    var service: Int
    @Provide(.transient, factory: PreparedOverrideReference())
    var reference: PreparedOverrideReference
}

@DIContainer
struct PreparedOptionalServices {
    @Provide(.shared, effect: .sideEffect, factory: Optional<Int>.some(41))
    var optional: Int?
    @Provide(.transient, factory: 1)
    var set: Int
    @Provide(.transient, factory: 2)
    var useDefault: Int
}

@DIContainerRole(role: ContainerRole.local, mainActor: true, generateOwned: true)
struct PreparedActorServices {
    @Input var counter: PreparedOverrideCounter
    @Provide(.shared, effect: .sideEffect, factory: { (counter: PreparedOverrideCounter) in counter.make() })
    var marked: Int
    @Provide(.shared, asyncFactory: { (marked: Int) async in marked + 1 })
    var service: Int
    @Provide(.transient, factory: PreparedActorLocalValue())
    var local: PreparedActorLocalValue
    @Provide(.shared, factory: Optional<Int>.some(41))
    var optional: Int?
}

@MainActor
@DIContainer(generateOwned: true)
struct PreparedExplicitActorServices {
    @Input var counter: PreparedOverrideCounter
    @Provide(.shared, effect: .sideEffect, factory: { (counter: PreparedOverrideCounter) in counter.make() })
    var marked: Int
    @Provide(.shared, asyncFactory: { (marked: Int) async in marked + 1 })
    var service: Int
    @Provide(.transient, factory: PreparedActorLocalValue())
    var local: PreparedActorLocalValue
}

@Suite("Prepared test override flow")
struct PreparedOverrideTests {
    @Test("strict method reference rejects missing effects before construction")
    func strictPresetPreflight() async throws {
        let counter = PreparedOverrideCounter()
        let missing = DIOverridePreset<PreparedEffectServices.Overrides>(name: "missing") { _ in }
        var operationRan = false

        await #expect(throws: DIMissingEffectOverrideError.self) {
            try await PreparedEffectServices.withPrepared(
                .service, counter: counter, overrides: missing.applyValidated
            ) { _ in
                operationRan = true
            }
        }

        #expect(counter.count == 0)
        #expect(!operationRan)
    }

    @Test("validated preset passes directly to withPrepared and retains transient identity")
    func validPresetAndTransientIdentity() async throws {
        let counter = PreparedOverrideCounter()
        let replacement = PreparedOverrideReference()
        let preset = DIOverridePreset<PreparedEffectServices.Overrides>(name: "offline") {
            $0.set(\.marked, to: 7)
            $0.set(\.reference, to: replacement)
        }

        let result = try await PreparedEffectServices.withPrepared(
            .service, counter: counter, overrides: preset.applyValidated
        ) { services in
            #expect(services.reference === replacement)
            #expect(services.reference === services.reference)
            return try await services.service
        }

        #expect(result == 8)
        #expect(counter.count == 0)
    }

    @Test("direct validated closure restores per-access transient construction")
    func ordinaryClosureAndTransientDefault() async throws {
        let counter = PreparedOverrideCounter()
        let result = try await PreparedEffectServices.withPrepared(
            .service, counter: counter,
            overrides: {
                $0.set(\.marked, to: 20)
                $0.set(\.reference, to: PreparedOverrideReference())
                $0.useDefault(\.reference)
                try DIOverrideEffectValidation.validate($0)
            }
        ) { services in
            #expect(services.reference !== services.reference)
            return try await services.service
        }
        #expect(result == 21)
        #expect(counter.count == 0)
    }

    @Test("explicit nil is present and restoring the default makes strict preflight fail again")
    func optionalNilAndDefaultRestoration() throws {
        var overrides = PreparedOptionalServices.Overrides()
        overrides.set(\.optional, to: nil)
        #expect(overrides.optional != nil)
        #expect(try DIOverrideEffectValidation.validate(overrides).isSatisfied)
        #expect(PreparedOptionalServices { $0 = overrides }.optional == nil)

        overrides.useDefault(\.optional)
        #expect(overrides.optional == nil)
        #expect(throws: DIMissingEffectOverrideError.self) {
            try DIOverrideEffectValidation.validate(overrides)
        }
        #expect(PreparedOptionalServices { $0 = overrides }.optional == 41)
    }

    @Test("helper names coexist with provider fields and reset transient defaults")
    func helperNameCollisionsAndDefaults() {
        var overrides = PreparedOptionalServices.Overrides()
        overrides.set(\.set, to: 11)
        overrides.set(\.useDefault, to: 22)
        let replaced = PreparedOptionalServices { $0 = overrides }
        #expect(replaced.set == 11)
        #expect(replaced.useDefault == 22)

        overrides.useDefault(\.set)
        overrides.useDefault(\.useDefault)
        let restored = PreparedOptionalServices { $0 = overrides }
        #expect(restored.set == 1)
        #expect(restored.useDefault == 2)
    }

    @Test("failed applyValidated preserves mutations and custom profiles remain explicit")
    func validationFailureAndRecordingProfile() throws {
        let preset = DIOverridePreset<PreparedOptionalServices.Overrides>(name: "partial") {
            $0.set(\.set, to: 11)
        }
        var overrides = PreparedOptionalServices.Overrides()
        #expect(throws: DIMissingEffectOverrideError.self) {
            try preset.applyValidated(to: &overrides)
        }
        #expect(overrides.set == 11)

        let recording = try preset.validated(base: .init(), profile: .recording)
        #expect(recording.set == 11)
        #expect(recording.missingEffectOverrides.map(\.providerName) == ["optional"])
    }

    @MainActor
    @Test("main-actor preset method reference validates before construction")
    func mainActorPreset() async throws {
        let counter = PreparedOverrideCounter()
        let missing = DIOverridePreset<PreparedActorServices.Overrides>(name: "missing") { _ in }
        await #expect(throws: DIMissingEffectOverrideError.self) {
            try await PreparedActorServices.withPrepared(
                .service, counter: counter, overrides: missing.applyValidated
            ) { _ in Issue.record("operation must not run") }
        }
        #expect(counter.count == 0)

        // DIOverridePreset keeps its existing nonisolated @Sendable closure.
        // Sendable stored override values can still be set directly.
        let preset = DIOverridePreset<PreparedActorServices.Overrides>(name: "offline") {
            $0.marked = 9
        }
        let result = try await PreparedActorServices.withPrepared(
            .service, counter: counter, overrides: preset.applyValidated
        ) { try await $0.service }
        #expect(result == 10)
        #expect(counter.count == 0)
    }

    @MainActor
    @Test("isolated closure supports non-Sendable values and explicit optional nil")
    func mainActorClosure() async throws {
        let counter = PreparedOverrideCounter()
        let replacement = PreparedActorLocalValue()
        let result = try await PreparedActorServices.withPrepared(
            .service, counter: counter,
            overrides: {
                $0.set(\.marked, to: 12)
                $0.set(\.local, to: replacement)
                $0.set(\.optional, to: nil)
                try DIOverrideEffectValidation.validate($0)
            }
        ) { services in
            #expect(services.local === replacement)
            #expect(services.local === services.local)
            #expect(services.optional == nil)
            return try await services.service
        }
        #expect(result == 13)
        #expect(counter.count == 0)
    }

    @MainActor
    @Test("source-written MainActor supports strict preset references and actor-bound closures")
    func explicitMainActor() async throws {
        let counter = PreparedOverrideCounter()
        let missing = DIOverridePreset<PreparedExplicitActorServices.Overrides>(name: "missing") { _ in }
        await #expect(throws: DIMissingEffectOverrideError.self) {
            try await PreparedExplicitActorServices.withPrepared(
                .service, counter: counter, overrides: missing.applyValidated
            ) { _ in Issue.record("operation must not run") }
        }
        #expect(counter.count == 0)

        let preset = DIOverridePreset<PreparedExplicitActorServices.Overrides>(name: "offline") {
            $0.marked = 29
        }
        let presetResult = try await PreparedExplicitActorServices.withPrepared(
            .service, counter: counter, overrides: preset.applyValidated
        ) { try await $0.service }
        #expect(presetResult == 30)

        let replacement = PreparedActorLocalValue()
        let closureResult = try await PreparedExplicitActorServices.withPrepared(
            .service, counter: counter,
            overrides: {
                $0.set(\.marked, to: 30)
                $0.set(\.local, to: replacement)
                try DIOverrideEffectValidation.validate($0)
            }
        ) { services in
            #expect(services.local === replacement)
            return try await services.service
        }
        #expect(closureResult == 31)
        #expect(counter.count == 0)
    }
}
