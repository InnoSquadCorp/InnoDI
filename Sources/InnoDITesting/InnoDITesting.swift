import Foundation
@_exported import InnoDI
import os

/// Small lock-backed value cell used by concurrency-safe generated mocks.
public final class DIConcurrentValueBox<Value: Sendable>: Sendable {
    private let storage: OSAllocatedUnfairLock<Value>

    public init(_ value: Value) {
        storage = OSAllocatedUnfairLock(initialState: value)
    }

    public func snapshot() -> Value {
        storage.withLock { $0 }
    }

    public func replace(with value: Value) {
        storage.withLock { $0 = value }
    }

    @discardableResult
    public func update<Result: Sendable>(
        _ body: @Sendable (inout Value) throws -> Result
    ) rethrows -> Result {
        try storage.withLock { value in
            try body(&value)
        }
    }
}

/// A lock-backed recorder for mocks that can be called from concurrent tasks.
public final class DIConcurrentCallRecorder<Call: Sendable>: Sendable {
    public struct Entry: Sendable {
        public let sequence: UInt64
        public let call: Call

        public init(sequence: UInt64, call: Call) {
            self.sequence = sequence
            self.call = call
        }
    }

    private struct State: Sendable {
        var nextSequence: UInt64 = 0
        var entries: [Entry] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    @discardableResult
    public func record(_ call: Call) -> UInt64 {
        state.withLock { state in
            let sequence = state.nextSequence
            state.nextSequence &+= 1
            state.entries.append(Entry(sequence: sequence, call: call))
            return sequence
        }
    }

    public func snapshot() -> [Entry] {
        state.withLock { $0.entries }
    }

    public var count: Int {
        state.withLock { $0.entries.count }
    }

    public func reset() {
        state.withLock { state in
            state.entries.removeAll(keepingCapacity: false)
            state.nextSequence = 0
        }
    }
}

/// Stable error used to stop a test before an unstubbed operation executes.
public struct DIMissingStubError: Error, Equatable, Sendable,
    CustomStringConvertible {
    public let selectors: [String]

    public init(selectors: [String]) {
        self.selectors = selectors
    }

    public var description: String {
        "Missing InnoDI mock stubs: \(selectors.joined(separator: ", "))"
    }
}

/// Validates generated or hand-written missing-stub selector lists.
public enum DIStubValidation {
    public static func requireAllStubbed(_ selectors: [String]) throws {
        guard selectors.isEmpty else {
            throw DIMissingStubError(selectors: selectors)
        }
    }
}

/// A deterministic summary of missing stubs and call-count mismatches.
public struct DIInteractionReport: Equatable, Sendable {
    public let missingStubSelectors: [String]
    public let missingCallCounts: [String: Int]
    public let unexpectedCallCounts: [String: Int]

    public init(
        missingStubSelectors: [String],
        missingCallCounts: [String: Int],
        unexpectedCallCounts: [String: Int]
    ) {
        self.missingStubSelectors = missingStubSelectors.sorted()
        self.missingCallCounts = missingCallCounts
        self.unexpectedCallCounts = unexpectedCallCounts
    }

    public var isSatisfied: Bool {
        missingStubSelectors.isEmpty
            && missingCallCounts.isEmpty
            && unexpectedCallCounts.isEmpty
    }
}

/// Error emitted by strict interaction validation after a test operation.
public struct DIInteractionViolationError: Error, Equatable, Sendable,
    CustomStringConvertible {
    public let report: DIInteractionReport

    public init(report: DIInteractionReport) {
        self.report = report
    }

    public var description: String {
        var parts: [String] = []
        if !report.missingStubSelectors.isEmpty {
            parts.append(
                "missing stubs: " + report.missingStubSelectors.joined(separator: ", ")
            )
        }
        if !report.missingCallCounts.isEmpty {
            parts.append("missing calls: " + Self.render(report.missingCallCounts))
        }
        if !report.unexpectedCallCounts.isEmpty {
            parts.append("unexpected calls: " + Self.render(report.unexpectedCallCounts))
        }
        return "InnoDI interaction validation failed (\(parts.joined(separator: "; ")))"
    }

    private static func render(_ counts: [String: Int]) -> String {
        counts.keys.sorted().map { "\($0)=\(counts[$0, default: 0])" }
            .joined(separator: ", ")
    }
}

/// Validates generated-mock setup and observed calls with an opt-in profile.
public enum DIInteractionValidation {
    @discardableResult
    public static func validate(
        missingStubSelectors: [String] = [],
        recordedCallCounts: [String: Int],
        expectedCallCounts: [String: Int],
        profile: DITestEffectProfile = .strict
    ) throws -> DIInteractionReport {
        let normalizedMissingStubs = Array(Set(missingStubSelectors)).sorted()
        let keys = Set(recordedCallCounts.keys).union(expectedCallCounts.keys)
        var missingCalls: [String: Int] = [:]
        var unexpectedCalls: [String: Int] = [:]

        for selector in keys {
            let actual = recordedCallCounts[selector, default: 0]
            let expected = expectedCallCounts[selector, default: 0]
            guard actual >= 0, expected >= 0 else {
                throw DIInteractionConfigurationError(selector: selector)
            }
            if actual < expected {
                missingCalls[selector] = expected - actual
            } else if actual > expected {
                unexpectedCalls[selector] = actual - expected
            }
        }

        let report = DIInteractionReport(
            missingStubSelectors: normalizedMissingStubs,
            missingCallCounts: missingCalls,
            unexpectedCallCounts: unexpectedCalls
        )
        let shouldFail = (
            profile.missingStub == .fail && !report.missingStubSelectors.isEmpty
        ) || (
            profile.unexpectedCall == .fail
                && (!report.missingCallCounts.isEmpty
                    || !report.unexpectedCallCounts.isEmpty)
        )
        if shouldFail {
            throw DIInteractionViolationError(report: report)
        }
        return report
    }
}

/// Invalid negative call counts are rejected instead of being normalized.
public struct DIInteractionConfigurationError: Error, Equatable, Sendable,
    CustomStringConvertible {
    public let selector: String

    public init(selector: String) {
        self.selector = selector
    }

    public var description: String {
        "InnoDI interaction counts must be nonnegative for '\(selector)'."
    }
}

/// A named, typed override transformation for tests and previews.
public struct DIOverridePreset<Overrides>: Sendable {
    public let name: String
    private let applyClosure: @Sendable (inout Overrides) -> Void

    public init(
        name: String,
        apply: @escaping @Sendable (inout Overrides) -> Void
    ) {
        self.name = name
        self.applyClosure = apply
    }

    public func apply(to overrides: inout Overrides) {
        applyClosure(&overrides)
    }

    public func callAsFunction(_ overrides: inout Overrides) {
        apply(to: &overrides)
    }

    /// Combines presets in explicit left-to-right order. Later writes win.
    public func combined(with later: Self, name: String? = nil) -> Self {
        Self(name: name ?? "\(self.name)+\(later.name)") { overrides in
            self.apply(to: &overrides)
            later.apply(to: &overrides)
        }
    }
}

public enum DIEffectViolationPolicy: String, Equatable, Sendable {
    case fail
    case record
}

/// Opt-in policy carried by test presets; strict behavior is never global.
public struct DITestEffectProfile: Equatable, Sendable {
    public let unexpectedCall: DIEffectViolationPolicy
    public let missingStub: DIEffectViolationPolicy

    public init(
        unexpectedCall: DIEffectViolationPolicy,
        missingStub: DIEffectViolationPolicy
    ) {
        self.unexpectedCall = unexpectedCall
        self.missingStub = missingStub
    }

    public static let strict = Self(
        unexpectedCall: .fail,
        missingStub: .fail
    )

    public static let recording = Self(
        unexpectedCall: .record,
        missingStub: .record
    )
}
