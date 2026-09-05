import InnoDITesting
import Testing

private struct RecordedCall: Equatable, Sendable {
    let value: Int
}

private struct PresetOverrides {
    var endpoint = "live"
    var retries = 0
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
        #expect(DITestEffectProfile.recording.unexpectedCall == .record)
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
