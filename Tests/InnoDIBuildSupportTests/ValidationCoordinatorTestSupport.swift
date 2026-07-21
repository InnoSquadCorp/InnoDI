import Foundation
import InnoDICore
import InnoDIWorkspaceAnalysis
import SwiftParser
import SwiftSyntax
import Testing
import Dispatch

@testable import InnoDIBuildSupport

final class MockValidationSyntaxParser: @unchecked Sendable, ValidationSyntaxParsing {
    private let lock = NSLock()
    private var storage: [String] = []

    var parsedSources: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var parseCount: Int {
        parsedSources.count
    }

    func parse(source: String) -> SourceFileSyntax {
        lock.lock()
        storage.append(source)
        lock.unlock()
        return Parser.parse(source: source)
    }
}

struct FixturePaths {
    let rootURL: URL
    let stateURL: URL
    let outputAURL: URL
    let outputBURL: URL
}

func loadDigestManifest(at url: URL) throws -> ValidationDigestManifest {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(ValidationDigestManifest.self, from: data)
}

func loadMetricsArtifact(at url: URL) throws -> ValidationMetricsArtifact {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(ValidationMetricsArtifact.self, from: data)
}

func loadSharedValidationRunRecord(at url: URL) throws -> SharedValidationRunRecord {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(SharedValidationRunRecord.self, from: data)
}

func persistJSON<Value: Encodable>(_ value: Value, to url: URL) throws {
    let data = try JSONEncoder().encode(value)
    try data.write(to: url, options: .atomic)
}

func makeFixture() throws -> FixturePaths {
    let rootURL = try makeTemporaryRoot()
    let stateURL = rootURL.appendingPathComponent("state", isDirectory: true)
    let outputAURL = rootURL.appendingPathComponent("output-a", isDirectory: true)
    let outputBURL = rootURL.appendingPathComponent("output-b", isDirectory: true)

    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outputAURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outputBURL, withIntermediateDirectories: true)

    try "struct Feature { let value = 1 }\n".write(
        to: rootURL.appendingPathComponent("Feature.swift"),
        atomically: true,
        encoding: .utf8
    )

    return FixturePaths(
        rootURL: rootURL,
        stateURL: stateURL,
        outputAURL: outputAURL,
        outputBURL: outputBURL
    )
}

func makeCrossFileCustomInitFixture() throws -> FixturePaths {
    let fixture = try makeFixture()

    try """
    @DIContainer
    struct AppContainer {
        @Provide(.input)
        var config: Config
    }
    """.write(
        to: fixture.rootURL.appendingPathComponent("Container.swift"),
        atomically: true,
        encoding: .utf8
    )

    try """
    extension AppContainer {
        init(config: Config, debug: Bool) {
            self.init(config: config)
        }
    }
    """.write(
        to: fixture.rootURL.appendingPathComponent("Container+Debug.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixture
}

func makeTemporaryRoot() throws -> URL {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-BuildSupport-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    return rootURL
}

func touch(_ url: URL, modifiedAt: Date) throws {
    try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path(percentEncoded: false))
}

func makeTestRuntime(
    clock: ManualValidationCoordinatorClock,
    currentPID: Int32,
    activePIDs: Set<Int32>,
    beforeStaleLockRemoval: @escaping @Sendable (URL) async -> Void = { _ in }
) -> ValidationCoordinatorRuntime {
    ValidationCoordinatorRuntime(
        monotonicNow: { clock.monotonicNow },
        currentDate: { clock.currentDate },
        sleep: { interval in clock.sleep(interval) },
        currentProcessID: { currentPID },
        processExists: { activePIDs.contains($0) },
        beforeStaleLockRemoval: beforeStaleLockRemoval
    )
}

final class ManualValidationCoordinatorClock: @unchecked Sendable {
    private let lock = NSLock()
    private let onSleep: (@Sendable (TimeInterval) -> Void)?
    private var uptime: TimeInterval
    private var date: Date
    private var recordedSleeps: [TimeInterval] = []

    init(
        startUptime: TimeInterval,
        startDate: Date,
        onSleep: (@Sendable (TimeInterval) -> Void)? = nil
    ) {
        self.onSleep = onSleep
        self.uptime = startUptime
        self.date = startDate
    }

    var monotonicNow: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return uptime
    }

    var currentDate: Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    var sleptDurations: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return recordedSleeps
    }

    var totalSlept: TimeInterval {
        sleptDurations.reduce(0, +)
    }

    func sleep(_ interval: TimeInterval) {
        lock.lock()
        uptime += interval
        date = date.addingTimeInterval(interval)
        recordedSleeps.append(interval)
        let onSleep = self.onSleep
        lock.unlock()

        onSleep?(interval)
    }
}

final class OneShotAsyncSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isSignaled {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }

    func signal() {
        lock.lock()
        guard isSignaled == false else {
            lock.unlock()
            return
        }
        isSignaled = true
        let currentWaiters = waiters
        waiters.removeAll(keepingCapacity: false)
        lock.unlock()

        for waiter in currentWaiters {
            waiter.resume()
        }
    }
}

final class SleepThresholdState: @unchecked Sendable {
    private let lock = NSLock()
    private let threshold: TimeInterval
    private var totalSlept: TimeInterval = 0
    private var didTrigger = false

    init(threshold: TimeInterval) {
        self.threshold = threshold
    }

    func shouldTrigger(afterSleeping interval: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        totalSlept += interval
        guard didTrigger == false, totalSlept >= threshold else {
            return false
        }

        didTrigger = true
        return true
    }
}

final class MockValidationRunner: ValidationCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let results: [ValidationCommandResult]
    private let delay: TimeInterval
    private var currentInvocationCount = 0

    init(results: [ValidationCommandResult], delay: TimeInterval = 0) {
        self.results = results
        self.delay = delay
    }

    var invocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return currentInvocationCount
    }

    func runValidationTool(
        toolPath: String?,
        rootPath: String,
        snapshot: WorkspaceSourceSnapshot
    ) throws -> ValidationCommandResult {
        lock.lock()
        let invocationIndex = currentInvocationCount
        currentInvocationCount += 1
        lock.unlock()

        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }

        if invocationIndex < results.count {
            return results[invocationIndex]
        }

        return results.last ?? ValidationCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
}
