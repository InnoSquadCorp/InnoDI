import InnoDITesting
import Testing

private struct RecordedCall: Equatable, Sendable {
    let value: Int
}

private struct GenerationCall: Equatable, Sendable {
    let generation: UInt64
    let value: Int
}

private struct GenerationReset: Equatable, Sendable {
    let generation: UInt64
    let count: Int
}

private struct PresetOverrides {
    var endpoint = "live"
    var retries = 0
}

struct EffectService: Equatable, Sendable {
    let id: Int
}

final class EffectFactoryCounter: Sendable {
    private let countBox = DIConcurrentValueBox(0)

    var count: Int { countBox.snapshot() }

    func make() -> EffectService {
        countBox.update { $0 += 1 }
        return EffectService(id: -1)
    }
}

@DIContainer
struct EffectContainer {
    @Input
    var counter: EffectFactoryCounter

    @Provide(
        .shared,
        effect: .sideEffect,
        factory: { (counter: EffectFactoryCounter) in counter.make() }
    )
    var service: EffectService
}

@DIContainer
struct OptionalEffectContainer {
    @Provide(
        .shared,
        effect: .sideEffect,
        factory: Optional<EffectService>.none
    )
    var service: EffectService?
}

@DIContainerRole(role: ContainerRole.local, mainActor: true)
struct MainActorEffectContainer {
    @Provide(.shared, effect: .sideEffect, factory: EffectService(id: -1))
    var service: EffectService
}

@Suite("InnoDITesting public product")
struct InnoDITestingTests {
    @Test("concurrent recorder preserves every call and resets atomically")
    func concurrentRecorder() async {
        let recorder = DIConcurrentCallRecorder<RecordedCall>()
        await withTaskGroup(of: Void.self) { group in
            for value in 0..<100 {
                group.addTask {
                    recorder.record(RecordedCall(value: value))
                }
            }
        }

        let entries = recorder.snapshot()
        #expect(entries.count == 100)
        #expect(Set(entries.map(\.sequence)).count == 100)
        #expect(Set(entries.map(\.call.value)) == Set(0..<100))

        recorder.reset()
        #expect(recorder.count == 0)
        #expect(recorder.record(RecordedCall(value: 101)) == 0)
    }

    @Test("concurrent value box updates and replaces atomically")
    func concurrentValueBox() async {
        let box = DIConcurrentValueBox(0)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    box.update { $0 += 1 }
                }
            }
        }
        #expect(box.snapshot() == 100)
        box.replace(with: 7)
        #expect(box.snapshot() == 7)
    }

    @Test("concurrent mock state linearizes calls snapshots and reset generations")
    func concurrentMockState() async {
        let state = DIConcurrentMockState()
        let calls = DIConcurrentValueBox<[GenerationCall]>([])
        let reset = DIConcurrentValueBox<GenerationReset?>(nil)
        let snapshots = DIConcurrentValueBox<[GenerationReset]>([])

        await withTaskGroup(of: Void.self) { group in
            for value in 0..<100 {
                group.addTask {
                    state.withCriticalRegion { generation in
                        calls.update {
                            $0.append(.init(
                                generation: generation,
                                value: value
                            ))
                        }
                    }
                }
            }
            group.addTask {
                let captured = state.reset { generation in
                    let captured = GenerationReset(
                        generation: generation,
                        count: calls.snapshot().count
                    )
                    calls.replace(with: [])
                    return captured
                }
                reset.replace(with: captured)
            }
            group.addTask {
                for _ in 0..<100 {
                    let snapshot = state.withCriticalRegion { generation in
                        GenerationReset(
                            generation: generation,
                            count: calls.snapshot().count
                        )
                    }
                    snapshots.update { $0.append(snapshot) }
                }
            }
        }

        let previous = reset.snapshot()
        let current = state.withCriticalRegion { generation in
            GenerationReset(
                generation: generation,
                count: calls.snapshot().count
            )
        }
        #expect(previous?.generation == 0)
        #expect(current.generation == 1)
        #expect((previous?.count ?? 0) + current.count == 100)
        #expect(calls.snapshot().allSatisfy { $0.generation == 1 })
        #expect(Set(calls.snapshot().map(\.value)).count == current.count)
        #expect(snapshots.snapshot().allSatisfy {
            (0...1).contains($0.generation) && $0.count >= 0
        })
    }

    @Test("typed presets compose left to right without cross-test state")
    func presetComposition() {
        let local = DIOverridePreset<PresetOverrides>(name: "local") {
            $0.endpoint = "local"
            $0.retries = 1
        }
        let offline = DIOverridePreset<PresetOverrides>(name: "offline") {
            $0.endpoint = "offline"
        }
        let combined = local.combined(with: offline)
        var first = PresetOverrides()
        var second = PresetOverrides()

        combined(&first)
        local(&second)

        #expect(first.endpoint == "offline")
        #expect(first.retries == 1)
        #expect(second.endpoint == "local")
        #expect(second.retries == 1)
        #expect(combined.name == "local+offline")
        #expect(DITestEffectProfile.strict.missingStub == .fail)
        #expect(DITestEffectProfile.strict.missingEffectOverride == .fail)
        #expect(DITestEffectProfile.recording.unexpectedCall == .record)
        #expect(DITestEffectProfile.recording.missingEffectOverride == .record)
    }

    @Test("strict effect validation stops before a live factory and accepts a complete preset")
    func strictEffectOverridePreflight() throws {
        let counter = EffectFactoryCounter()
        let missing = DIProviderEffectRequirement(
            providerName: "service",
            effect: .sideEffect
        )
        #expect(EffectContainer.Overrides.requiredEffectOverrides == [missing])
        #expect(throws: DIMissingEffectOverrideError(
            report: DIOverrideEffectReport(missing: [missing])
        )) {
            try DIOverrideEffectValidation.validate(EffectContainer.Overrides())
        }
        #expect(counter.count == 0)

        let preset = DIOverridePreset<EffectContainer.Overrides>(name: "mock") {
            $0.service = EffectService(id: 7)
        }
        let overrides = try preset.validated(base: EffectContainer.Overrides())
        let container = EffectContainer(counter: counter) { $0 = overrides }

        #expect(container.service == EffectService(id: 7))
        #expect(counter.count == 0)
    }

    @Test("effect presets compose left to right and remain task-local")
    func effectPresetCompositionAndParallelIsolation() async throws {
        let early = DIOverridePreset<EffectContainer.Overrides>(name: "early") {
            $0.service = EffectService(id: 1)
        }
        let late = DIOverridePreset<EffectContainer.Overrides>(name: "late") {
            $0.service = EffectService(id: 2)
        }
        let combined = early.combined(with: late)
        let combinedOverrides = try combined.validated(
            base: EffectContainer.Overrides()
        )
        let counter = EffectFactoryCounter()
        let combinedContainer = EffectContainer(counter: counter) {
            $0 = combinedOverrides
        }
        #expect(combinedContainer.service.id == 2)
        #expect(counter.count == 0)

        let ids = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
            for id in 0..<100 {
                group.addTask {
                    let local = DIOverridePreset<EffectContainer.Overrides>(name: "task-\(id)") {
                        $0.service = EffectService(id: id)
                    }
                    let overrides = try! local.validated(
                        base: EffectContainer.Overrides()
                    )
                    let localCounter = EffectFactoryCounter()
                    let container = EffectContainer(counter: localCounter) {
                        $0 = overrides
                    }
                    return localCounter.count == 0 ? container.service.id : -1
                }
            }
            var values: [Int] = []
            for await value in group {
                values.append(value)
            }
            return values
        }
        #expect(Set(ids) == Set(0..<100))
    }

    @Test("explicit optional nil satisfies the outer override slot")
    func optionalNilEffectOverride() throws {
        var overrides = OptionalEffectContainer.Overrides()
        overrides.service = .some(nil)
        let report = try DIOverrideEffectValidation.validate(overrides)
        #expect(report.isSatisfied)

        let container = OptionalEffectContainer { $0 = overrides }
        #expect(container.service == nil)
    }

    @MainActor
    @Test("main-actor effect overrides use the isolated validator")
    func mainActorEffectOverride() throws {
        var overrides = MainActorEffectContainer.Overrides()
        overrides.service = EffectService(id: 3)
        let report = try DIOverrideEffectValidation.validate(overrides)
        #expect(report.isSatisfied)
    }

    @Test("production construction does not enable strict validation globally")
    func productionDefaultRemainsUnchanged() {
        let counter = EffectFactoryCounter()
        let container = EffectContainer(counter: counter) { _ in }
        #expect(container.service == EffectService(id: -1))
        #expect(counter.count == 1)
    }

    @Test("missing stubs fail before an operation runs")
    func missingStubValidation() {
        #expect(throws: DIMissingStubError(selectors: ["fetch"])) {
            try DIStubValidation.requireAllStubbed(["fetch"])
        }
        #expect(throws: Never.self) {
            try DIStubValidation.requireAllStubbed([])
        }
    }

    @Test("strict interactions fail and recording profile returns the same report")
    func interactionValidation() throws {
        let expected = DIInteractionReport(
            missingStubSelectors: ["load"],
            missingCallCounts: ["save": 1],
            unexpectedCallCounts: ["fetch": 1]
        )
        #expect(throws: DIInteractionViolationError(report: expected)) {
            try DIInteractionValidation.validate(
                missingStubSelectors: ["load", "load"],
                recordedCallCounts: ["fetch": 2],
                expectedCallCounts: ["fetch": 1, "save": 1]
            )
        }

        let report = try DIInteractionValidation.validate(
            missingStubSelectors: ["load"],
            recordedCallCounts: ["fetch": 2],
            expectedCallCounts: ["fetch": 1, "save": 1],
            profile: .recording
        )
        #expect(report == expected)
        #expect(!report.isSatisfied)

        let satisfied = try DIInteractionValidation.validate(
            recordedCallCounts: ["fetch": 1],
            expectedCallCounts: ["fetch": 1]
        )
        #expect(satisfied.isSatisfied)
        #expect(throws: DIInteractionConfigurationError(selector: "fetch")) {
            try DIInteractionValidation.validate(
                recordedCallCounts: ["fetch": -1],
                expectedCallCounts: [:]
            )
        }
    }
}
