import Foundation
import InnoDICore
import InnoDIWorkspaceAnalysis
import SwiftParser
import SwiftSyntax
import Testing
import Dispatch

@testable import InnoDIBuildSupport

/// Shared-run caching, lock recovery, and terminal coordination contracts.
extension ValidationCoordinatorTests {
    @Test("Legacy shared-run cache directories without a version salt are ignored")
    func legacySharedRunCacheDirectoriesAreIgnored() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let signature = try collectValidationSignature(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false)
        )
        let legacyDirectory = fixture.stateURL.appendingPathComponent(signature, isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try persistJSON(
            ValidationCommandResult(exitCode: 0, stdout: "legacy\n", stderr: ""),
            to: legacyDirectory.appendingPathComponent("result.json")
        )
        try persistJSON(
            SharedValidationRunRecord(
                liveRunMetrics: ValidationLiveRunMetrics(
                    customInitValidationMilliseconds: 1,
                    semanticValidationMilliseconds: 1,
                    hierarchyValidationMilliseconds: 0,
                    dagValidationMilliseconds: 1
                ),
                reasonCodes: [.liveRunSemanticValidation, .liveRunDAGValidation],
                issues: []
            ),
            to: legacyDirectory.appendingPathComponent("validation-metrics.json")
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "fresh\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.wasCached == false)
        #expect(outcome.result.stdout == "fresh\n")
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticValidation))
        #expect(runner.invocationCount == 1)
        #expect(FileManager.default.fileExists(atPath: legacyDirectory.path(percentEncoded: false)) == false)
    }

    @Test("Corrupt current-version shared-run metrics fall back to a live validation run")
    func corruptCurrentVersionSharedRunMetricsFallBackToLiveRun() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let signature = try collectValidationSignature(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false)
        )
        let sharedRunDirectory = fixture.stateURL.appendingPathComponent(
            sharedRunCacheKey(for: signature),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: sharedRunDirectory, withIntermediateDirectories: true)
        try persistJSON(
            ValidationCommandResult(exitCode: 0, stdout: "legacy\n", stderr: ""),
            to: sharedRunDirectory.appendingPathComponent("result.json")
        )
        try Data("{\"liveRunMetrics\":{}}".utf8).write(
            to: sharedRunDirectory.appendingPathComponent("validation-metrics.json"),
            options: .atomic
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "fresh\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.wasCached == false)
        #expect(outcome.result.stdout == "fresh\n")
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticValidation))
        #expect(runner.invocationCount == 1)

        let repairedRecord = try loadSharedValidationRunRecord(
            at: sharedRunDirectory.appendingPathComponent("validation-metrics.json")
        )
        #expect(repairedRecord.liveRunMetrics.semanticValidationMilliseconds >= 0)
    }

    @Test("Dead-owner lock files are recovered before live validation continues")
    func deadOwnerLockIsRecoveredBeforeLiveValidation() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let signature = try collectValidationSignature(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false)
        )
        let sharedRunDirectory = fixture.stateURL.appendingPathComponent(
            sharedRunCacheKey(for: signature),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: sharedRunDirectory, withIntermediateDirectories: true)

        let clock = ManualValidationCoordinatorClock(
            startUptime: 100,
            startDate: Date(timeIntervalSince1970: 10_000)
        )
        try persistJSON(
            ValidationCoordinatorLockMetadata(
                pid: 1111,
                createdAt: clock.currentDate.addingTimeInterval(-120).timeIntervalSince1970
            ),
            to: sharedRunDirectory.appendingPathComponent("lock")
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "DAG validation passed.\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner,
            lockPolicy: .default,
            runtime: makeTestRuntime(clock: clock, currentPID: 4242, activePIDs: [4242])
        )

        #expect(outcome.result.exitCode == 0)
        #expect(outcome.metricsArtifact.reasonCodes.contains(ValidationReasonCode.staleLockRecovered))
        #expect(outcome.metricsArtifact.reasonCodes.contains(ValidationReasonCode.liveRunDAGValidation))
        #expect(runner.invocationCount == 1)
        #expect(clock.sleptDurations.isEmpty)
    }

    @Test("Corrupt legacy lock files older than the stale threshold are recovered")
    func corruptLegacyLockFileIsRecovered() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let signature = try collectValidationSignature(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false)
        )
        let sharedRunDirectory = fixture.stateURL.appendingPathComponent(
            sharedRunCacheKey(for: signature),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: sharedRunDirectory, withIntermediateDirectories: true)

        let clock = ManualValidationCoordinatorClock(
            startUptime: 50,
            startDate: Date(timeIntervalSince1970: 20_000)
        )
        let lockURL = sharedRunDirectory.appendingPathComponent("lock")
        try Data("legacy-lock".utf8).write(to: lockURL, options: .atomic)
        try touch(lockURL, modifiedAt: clock.currentDate.addingTimeInterval(-120))

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "DAG validation passed.\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner,
            lockPolicy: .default,
            runtime: makeTestRuntime(clock: clock, currentPID: 4242, activePIDs: [4242])
        )

        #expect(outcome.result.exitCode == 0)
        #expect(outcome.metricsArtifact.reasonCodes.contains(ValidationReasonCode.staleLockRecovered))
        #expect(runner.invocationCount == 1)
        #expect(clock.sleptDurations.isEmpty)
    }

    @Test("releaseLock removes the matching lock file")
    func releaseLockRemovesMatchingLockFile() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let lockURL = rootURL.appendingPathComponent("validation.lock")
        let descriptor = try #require(try acquireLock(at: lockURL))

        #expect(FileManager.default.fileExists(atPath: lockURL.path(percentEncoded: false)))

        releaseLock(descriptor: descriptor, at: lockURL)

        #expect(FileManager.default.fileExists(atPath: lockURL.path(percentEncoded: false)) == false)
    }

    @Test("acquireLock holds an advisory flock that blocks a second acquirer on the same descriptor")
    func acquireLockHoldsAdvisoryFlock() throws {
        // Item 1.C — `acquireLock` layers `flock(LOCK_EX | LOCK_NB)`
        // on top of `O_CREAT | O_EXCL`. We assert the advisory layer
        // is actually held by opening the same path independently
        // (without O_EXCL, so the open itself does not contend) and
        // confirming flock reports `EWOULDBLOCK`.
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let lockURL = rootURL.appendingPathComponent("validation.lock")
        let descriptor = try #require(try acquireLock(at: lockURL))
        defer { releaseLock(descriptor: descriptor, at: lockURL) }

        // Independent descriptor pointing at the same inode.
        let path = lockURL.path(percentEncoded: false)
        let secondDescriptor = path.withCString { open($0, O_RDWR) }
        try #require(secondDescriptor >= 0)
        defer { close(secondDescriptor) }

        let result = flock(secondDescriptor, LOCK_EX | LOCK_NB)
        let savedErrno = errno
        #expect(result == -1, "Expected flock contention; got result \(result)")
        #expect(
            savedErrno == EWOULDBLOCK || savedErrno == EAGAIN,
            "Expected EWOULDBLOCK/EAGAIN; got errno \(savedErrno)"
        )
    }

    @Test("acquireLock removes the lock file after release and allows reacquire")
    func acquireLockDoesNotLeaveLockFileAfterReleaseAndReacquire() throws {
        // Indirect coverage: O_EXCL prevents directly reproducing a lone
        // advisory-flock failure in acquireLock. This exercises the cleanup
        // path around ValidationCoordinator+Locking.swift's close/removeItem
        // pairing by acquiring, releasing, confirming the file is gone, and
        // reacquiring at the same path.
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let lockURL = rootURL.appendingPathComponent("validation.lock")
        let first = try #require(try acquireLock(at: lockURL))
        releaseLock(descriptor: first, at: lockURL)

        #expect(FileManager.default.fileExists(atPath: lockURL.path(percentEncoded: false)) == false)

        let second = try #require(try acquireLock(at: lockURL))
        releaseLock(descriptor: second, at: lockURL)
    }

    @Test("lock policy warns on invalid allow-unsafe environment value")
    func lockPolicyWarnsOnInvalidAllowUnsafeEnvironmentValue() {
        var warnings: [String] = []
        let policy = ValidationCoordinatorLockPolicy(
            environment: [
                ValidationCoordinatorLockPolicy.EnvKey.allowUnsafeLock: "maybe"
            ],
            warningHandler: { warnings.append($0) }
        )

        #expect(policy.allowUnsafeFilesystem == false)
        #expect(warnings == [
            "InnoDI: ignoring invalid INNODI_ALLOW_UNSAFE_LOCK=maybe; falling back to false."
        ])
    }

    @Test("releaseLock does not delete a replacement file recreated at the same path")
    func releaseLockDoesNotDeleteReplacementFile() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let lockURL = rootURL.appendingPathComponent("validation.lock")
        let descriptor = try #require(try acquireLock(at: lockURL))

        try FileManager.default.removeItem(at: lockURL)
        try Data("replacement".utf8).write(to: lockURL, options: .atomic)

        releaseLock(descriptor: descriptor, at: lockURL)

        #expect(FileManager.default.fileExists(atPath: lockURL.path(percentEncoded: false)))
        let contents = try String(contentsOf: lockURL, encoding: .utf8)
        #expect(contents == "replacement")
    }

    @Test("Stale-lock recovery is serialized before a fresh live lock is acquired")
    func staleLockRecoveryIsSerializedBeforeFreshLiveLock() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let signature = try collectValidationSignature(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false)
        )
        let sharedRunDirectory = fixture.stateURL.appendingPathComponent(
            sharedRunCacheKey(for: signature),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: sharedRunDirectory, withIntermediateDirectories: true)

        let lockURL = sharedRunDirectory.appendingPathComponent("lock")
        try persistJSON(
            ValidationCoordinatorLockMetadata(
                pid: 1111,
                createdAt: Date().addingTimeInterval(-120).timeIntervalSince1970
            ),
            to: lockURL
        )

        let recoveryPointReached = OneShotAsyncSignal()
        let contenderReachedBackoff = OneShotAsyncSignal()
        let allowContenderRetry = OneShotAsyncSignal()
        let allowRecovery = OneShotAsyncSignal()
        defer {
            allowRecovery.signal()
            allowContenderRetry.signal()
        }

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "DAG validation passed.\n", stderr: "")
            ]
        )
        let policy = ValidationCoordinatorLockPolicy(
            // The contender is suspended at its first backoff until the
            // holder finishes, so scheduler starvation cannot consume the
            // budget before the intended interleaving is established.
            maxWaitSeconds: 1,
            staleLockAgeSeconds: 0.1,
            initialBackoffSeconds: 0.01,
            maxBackoffSeconds: 0.05
        )

        let runtimeA = ValidationCoordinatorRuntime(
            monotonicNow: validationNow,
            currentDate: Date.init,
            sleep: validationSleep,
            currentProcessID: { 2001 },
            processExists: { [2001, 2002].contains($0) },
            beforeStaleLockRemoval: { _ in
                recoveryPointReached.signal()
                await allowRecovery.wait()
            }
        )
        // Marks the moment the contender enters a coordinator wait loop: its
        // first backoff sleep can only happen after it observed the lock
        // state A is holding, which is the readiness point the test needs
        // before letting A's recovery proceed.
        let runtimeB = ValidationCoordinatorRuntime(
            monotonicNow: validationNow,
            currentDate: Date.init,
            sleep: { _ in
                contenderReachedBackoff.signal()
                await allowContenderRetry.wait()
            },
            currentProcessID: { 2002 },
            processExists: { [2001, 2002].contains($0) }
        )

        let holder = Task {
            try await ValidationCoordinator.coordinate(
                rootPath: fixture.rootURL.path(percentEncoded: false),
                toolPath: "/usr/bin/true",
                stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
                outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
                runner: runner,
                lockPolicy: policy,
                runtime: runtimeA
            )
        }
        await recoveryPointReached.wait()

        let contender = Task {
            try await ValidationCoordinator.coordinate(
                rootPath: fixture.rootURL.path(percentEncoded: false),
                toolPath: "/usr/bin/true",
                stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
                outputDirectoryPath: fixture.outputBURL.path(percentEncoded: false),
                runner: runner,
                lockPolicy: policy,
                runtime: runtimeB
            )
        }
        await contenderReachedBackoff.wait()

        allowRecovery.signal()
        let holderOutcome = try await holder.value
        allowContenderRetry.signal()
        let contenderOutcome = try await contender.value
        let outcomes = [holderOutcome, contenderOutcome]

        #expect(outcomes.count == 2)
        #expect(runner.invocationCount == 1)
        #expect(outcomes.contains { !$0.wasCached })
        #expect(outcomes.contains { $0.wasCached })
        #expect(outcomes.allSatisfy { $0.result.exitCode == 0 })
        #expect(outcomes.allSatisfy { $0.metricsArtifact.reasonCodes.contains(ValidationReasonCode.staleLockRecovered) })
        #expect(FileManager.default.fileExists(atPath: lockURL.appendingPathExtension("recovering").path(percentEncoded: false)) == false)
    }

    @Test("Terminal reconciliation returns a cached result written during the final backoff")
    func terminalReconciliationReturnsCachedResultWrittenDuringFinalBackoff() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let signature = try collectValidationSignature(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false)
        )
        let sharedRunDirectory = fixture.stateURL.appendingPathComponent(
            sharedRunCacheKey(for: signature),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: sharedRunDirectory, withIntermediateDirectories: true)

        let policy = ValidationCoordinatorLockPolicy(
            maxWaitSeconds: 0.3,
            staleLockAgeSeconds: 0.1,
            initialBackoffSeconds: 0.05,
            maxBackoffSeconds: 0.2
        )
        let cachedResult = ValidationCommandResult(exitCode: 0, stdout: "cached\n", stderr: "")
        let cachedRecord = SharedValidationRunRecord(
            liveRunMetrics: ValidationLiveRunMetrics(
                customInitValidationMilliseconds: 1,
                semanticValidationMilliseconds: 2,
                hierarchyValidationMilliseconds: 0,
                dagValidationMilliseconds: 3
            ),
            reasonCodes: [.liveRunSemanticValidation, .liveRunDAGValidation],
            issues: []
        )
        let lockURL = sharedRunDirectory.appendingPathComponent("lock")
        try persistJSON(
            ValidationCoordinatorLockMetadata(
                pid: 1111,
                createdAt: Date(timeIntervalSince1970: 30_000).timeIntervalSince1970
            ),
            to: lockURL
        )

        let cacheWriteState = SleepThresholdState(threshold: policy.maxWaitSeconds)
        let clock = ManualValidationCoordinatorClock(
            startUptime: 10,
            startDate: Date(timeIntervalSince1970: 30_000),
            onSleep: { interval in
                guard cacheWriteState.shouldTrigger(afterSleeping: interval) else {
                    return
                }

                try! persistJSON(cachedRecord, to: sharedRunDirectory.appendingPathComponent("validation-metrics.json"))
                try! persistJSON(cachedResult, to: sharedRunDirectory.appendingPathComponent("result.json"))
                try? FileManager.default.removeItem(at: lockURL)
            }
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner,
            lockPolicy: policy,
            runtime: makeTestRuntime(clock: clock, currentPID: 4242, activePIDs: [1111, 4242])
        )

        #expect(outcome.wasCached == true)
        #expect(outcome.result == cachedResult)
        #expect(outcome.metricsArtifact.reasonCodes.contains(ValidationReasonCode.liveRunSemanticValidation))
        #expect(outcome.metricsArtifact.reasonCodes.contains(ValidationReasonCode.liveRunDAGValidation))
        #expect(outcome.metricsArtifact.reasonCodes.contains(ValidationReasonCode.lockContentionTimeout) == false)
        #expect(clock.sleptDurations.count == 3)
        #expect(runner.invocationCount == 0)
    }

    @Test("Active locks time out predictably instead of retrying indefinitely")
    func activeLockTimesOutPredictably() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let signature = try collectValidationSignature(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false)
        )
        let sharedRunDirectory = fixture.stateURL.appendingPathComponent(
            sharedRunCacheKey(for: signature),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: sharedRunDirectory, withIntermediateDirectories: true)

        let clock = ManualValidationCoordinatorClock(
            startUptime: 10,
            startDate: Date(timeIntervalSince1970: 30_000)
        )
        try persistJSON(
            ValidationCoordinatorLockMetadata(
                pid: 1111,
                createdAt: clock.currentDate.timeIntervalSince1970
            ),
            to: sharedRunDirectory.appendingPathComponent("lock")
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )
        let policy = ValidationCoordinatorLockPolicy(
            maxWaitSeconds: 0.3,
            staleLockAgeSeconds: 0.1,
            initialBackoffSeconds: 0.05,
            maxBackoffSeconds: 0.2
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner,
            lockPolicy: policy,
            runtime: makeTestRuntime(clock: clock, currentPID: 4242, activePIDs: [1111, 4242])
        )

        let summary = try String(
            contentsOf: fixture.outputAURL.appendingPathComponent("dag-validation-summary.md"),
            encoding: .utf8
        )

        #expect(outcome.wasCached == false)
        #expect(outcome.result.exitCode == 1)
        // The lock-timeout stderr block is documented in
        // `Sources/InnoDI/InnoDI.docc/lock-safety.md`. Assert on the
        // structural elements rather than the exact wording so future
        // copy edits do not require lockstep test changes.
        let stderr = outcome.result.stderr
        #expect(stderr.contains("Timed out waiting"))
        #expect(stderr.contains("InnoDI validation coordinator lock"))
        #expect(stderr.contains("path:"))
        #expect(stderr.contains("waited:"))
        #expect(stderr.contains("Suggested actions:"))
        #expect(stderr.contains("INNODI_LOCK_TIMEOUT"))
        #expect(stderr.contains("--scratch-path"))
        #expect(outcome.metricsArtifact.reasonCodes.contains(ValidationReasonCode.lockContentionTimeout))
        #expect(outcome.metricsArtifact.issues.isEmpty)
        #expect(outcome.metricsArtifact.liveRunMetrics.customInitValidationMilliseconds == 0)
        #expect(outcome.metricsArtifact.liveRunMetrics.semanticValidationMilliseconds == 0)
        #expect(outcome.metricsArtifact.liveRunMetrics.dagValidationMilliseconds == 0)
        #expect(summary.contains("lock-contention-timeout"))
        #expect(summary.contains("timed out waiting for an active lock"))
        #expect(clock.sleptDurations.count == 3)
        #expect(clock.totalSlept >= policy.maxWaitSeconds)
        #expect(runner.invocationCount == 0)
    }

    @Test("Failure result is reused for identical input signature")
    func failureResultIsReused() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 3, stdout: "", stderr: "DAG validation failed.\n")
            ]
        )

        let first = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/false",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )
        let second = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/false",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputBURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(first.result.exitCode == 3)
        #expect(second.result.exitCode == 3)
        #expect(first.wasCached == false)
        #expect(second.wasCached == true)
        #expect(second.result.stderr == "DAG validation failed.\n")
        #expect(runner.invocationCount == 1)
    }

    @Test("Concurrent requests share one live validation run")
    func concurrentRequestsShareOneLiveValidationRun() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "DAG validation passed.\n", stderr: "")
            ],
            delay: 0.2
        )

        let outputCURL = fixture.rootURL.appendingPathComponent("output-c", isDirectory: true)
        let outputDURL = fixture.rootURL.appendingPathComponent("output-d", isDirectory: true)

        let results = try await withThrowingTaskGroup(of: ValidationExecutionOutcome.self) { group in
            group.addTask {
                try await ValidationCoordinator.coordinate(
                    rootPath: fixture.rootURL.path(percentEncoded: false),
                    toolPath: "/usr/bin/true",
                    stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
                    outputDirectoryPath: outputCURL.path(percentEncoded: false),
                    runner: runner
                )
            }
            group.addTask {
                try await ValidationCoordinator.coordinate(
                    rootPath: fixture.rootURL.path(percentEncoded: false),
                    toolPath: "/usr/bin/true",
                    stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
                    outputDirectoryPath: outputDURL.path(percentEncoded: false),
                    runner: runner
                )
            }

            var collected: [ValidationExecutionOutcome] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }

        #expect(results.count == 2)
        #expect(runner.invocationCount == 1)
        #expect(results.contains { $0.wasCached })
        #expect(results.contains { !$0.wasCached })
        #expect(results.reduce(0) { $0 + $1.metricsArtifact.signatureMetrics.astReparseCount } == 1)
        #expect(results.contains { $0.metricsArtifact.signatureMetrics.metadataCacheHitCount == 1 })
    }

    @Test("Changing source input invalidates the cached result")
    func changingSourceInputInvalidatesCache() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "first\n", stderr: ""),
                ValidationCommandResult(exitCode: 0, stdout: "second\n", stderr: "")
            ]
        )

        let first = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        try "struct Feature { let value = 2 }\n".write(
            to: fixture.rootURL.appendingPathComponent("Feature.swift"),
            atomically: true,
            encoding: .utf8
        )

        let second = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputBURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(first.wasCached == false)
        #expect(second.wasCached == false)
        #expect(first.signature != second.signature)
        #expect(runner.invocationCount == 2)
    }

    @Test("Cross-file custom init validation fails before DAG runner executes")
    func crossFileCustomInitValidationFailsBeforeRunnerExecutes() async throws {
        let fixture = try makeCrossFileCustomInitFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(outcome.result.stderr.contains("container.custom-init-unsupported"))
        #expect(outcome.result.stderr.contains("extension"))
        #expect(outcome.metricsArtifact.issues.count == 1)
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunCustomInitFailure))
        #expect(runner.invocationCount == 0)
    }

    @Test("Full-source qualifier validation fails before DAG runner executes")
    func qualifierValidationFailsBeforeRunnerExecutes() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        @DIContainer(mainActor: true)
        struct AppContainer {
            @Provide(.input) var value: Int
        }
        """.write(
            to: fixture.rootURL.appendingPathComponent("Container.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "struct Swift {}\n".write(
            to: fixture.rootURL.appendingPathComponent("QualifierShadow.swift"),
            atomically: true,
            encoding: .utf8
        )
        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(
                    exitCode: 0,
                    stdout: "unexpected\n",
                    stderr: ""
                )
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(
            outcome.metricsArtifact.issues.map(\.code) == [
                "container.reserved-module-name"
            ]
        )
        #expect(
            outcome.metricsArtifact.reasonCodes.contains(
                .liveRunSemanticFailure
            )
        )
        #expect(runner.invocationCount == 0)
    }

    @Test("Unsupported container declarations fail once before downstream validation")
    func unsupportedContainerDeclarationFailsBeforeRunnerExecutes() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        @DIComponent
        @DIContainer
        final class UnsupportedContainer {
            @Provide(.input)
            var config: String = ""

            @SubContainer(scope: .shared)
            var child: ChildContainer = ChildContainer()

            init() {}
        }

        @DIContainer
        struct ChildContainer {}
        """.write(
            to: fixture.rootURL.appendingPathComponent("UnsupportedContainer.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(outcome.metricsArtifact.issues.count == 1)
        #expect(
            outcome.metricsArtifact.issues.first?.code
                == "container.unsupported-declaration-kind"
        )
        #expect(!outcome.result.stderr.contains("container.custom-init-unsupported"))
        #expect(!outcome.result.stderr.contains("sub."))
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticFailure))
        #expect(runner.invocationCount == 0)
    }

    @Test("Private container declarations fail before downstream validation")
    func privateContainerDeclarationFailsBeforeRunnerExecutes() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        @DIContainer
        private struct PrivateContainer {}
        """.write(
            to: fixture.rootURL.appendingPathComponent("PrivateContainer.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(outcome.metricsArtifact.issues.count == 1)
        #expect(
            outcome.metricsArtifact.issues.first?.code
                == "container.private-access-unsupported"
        )
        #expect(
            outcome.metricsArtifact.issues.first?.message.contains(
                "'PrivateContainer' cannot be declared private"
            ) == true
        )
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticFailure))
        #expect(runner.invocationCount == 0)
    }

    @Test("Full-source preflight rejects containers inside computed-property accessors")
    func accessorLocalContainerFailsBeforeRunnerExecutes() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        struct AccessorHost {
            var value: Int {
                @DIContainer
                struct AccessorContainer {}
                return 0
            }
        }
        """.write(
            to: fixture.rootURL.appendingPathComponent("AccessorContainer.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "unexpected\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(outcome.metricsArtifact.issues.count == 1)
        #expect(
            outcome.metricsArtifact.issues.first?.code
                == "container.local-declaration-unsupported"
        )
        #expect(
            outcome.metricsArtifact.issues.first?.message.contains(
                "'AccessorContainer' is declared in an executable code scope"
            ) == true
        )
        #expect(outcome.metricsArtifact.reasonCodes.contains(.liveRunSemanticFailure))
        #expect(runner.invocationCount == 0)
    }

    @Test("Same-file extension custom init conflicts fail before compilation")
    func sameFileCustomInitConflictsShortCircuitBuildValidator() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        try """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config
        }

        extension AppContainer {
            init(config: Config, debug: Bool) {
                self.init(config: config)
            }
        }
        """.write(
            to: fixture.rootURL.appendingPathComponent("Container.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runner = MockValidationRunner(
            results: [
                ValidationCommandResult(exitCode: 0, stdout: "DAG validation passed.\n", stderr: "")
            ]
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputAURL.path(percentEncoded: false),
            runner: runner
        )

        #expect(outcome.result.exitCode == 1)
        #expect(outcome.metricsArtifact.issues.count == 1)
        #expect(
            outcome.metricsArtifact.issues.first?.code
                == MacroBuildDiagnosticContract
                    .containerCustomInitUnsupportedCode
        )
        #expect(
            outcome.metricsArtifact.issues.first?.message
                == MacroBuildDiagnosticContract
                    .containerCustomInitUnsupportedMessage
        )
        #expect(outcome.result.stderr.contains("extension"))
        #expect(runner.invocationCount == 0)
    }

    @Test("Conditional same-file extension initializers participate in build validation")
    func conditionalSameFileExtensionInitializersAreRejected() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config
        }

        extension AppContainer {
            #if os(macOS)
            init(config: Config, debug: Bool) {
                self.init(config: config)
            }
            #endif
        }
        """.write(
            to: rootURL.appendingPathComponent("Container.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try CustomInitBuildValidator.validate(
            rootPath: rootURL.path(percentEncoded: false)
        )

        #expect(result.issues.count == 1)
        #expect(result.issues.first?.code == "container.custom-init-unsupported")
        #expect(result.issues.first?.metadata["containerPath"] == "AppContainer")
    }

    @Test("Cross-file validator matches nested paths exactly and ignores generic or constrained extensions")
    func crossFileValidatorRespectsExtensionMatchingBoundaries() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try """
        struct Outer {
            @DIContainer
            struct NestedContainer {
                @Provide(.input)
                var config: Config
            }
        }

        // Syntax-only validator boundary fixture. InnoDI 5.0 rejects this
        // declaration during macro expansion; it is not a supported example.
        @DIContainer
        struct GenericContainer<T> {
            @Provide(.input)
            var config: Config
        }
        """.write(
            to: rootURL.appendingPathComponent("Containers.swift"),
            atomically: true,
            encoding: .utf8
        )

        try """
        extension Outer.NestedContainer {
            init(config: Config, debug: Bool) {
                self.init(config: config)
            }
        }

        extension GenericContainer<String> {
            init(config: Config, preview: Bool) {
                self.init(config: config)
            }
        }

        extension GenericContainer where T: Sendable {
            init(config: Config, retries: Int) {
                self.init(config: config)
            }
        }
        """.write(
            to: rootURL.appendingPathComponent("Extensions.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try CustomInitBuildValidator.validate(rootPath: rootURL.path(percentEncoded: false))

        #expect(result.issues.count == 1)
        #expect(result.issues.first?.metadata["containerPath"] == "Outer.NestedContainer")
    }

    @Test("Qualified InnoDI containers participate in custom-init build validation")
    func qualifiedContainersParticipateInCustomInitBuildValidation() throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try """
        struct Config {}

        @InnoDI.DIContainer
        struct AppContainer {
            @InnoDI.Provide(.input)
            var config: Config
        }
        """.write(
            to: rootURL.appendingPathComponent("QualifiedContainer.swift"),
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
            to: rootURL.appendingPathComponent("QualifiedContainer+Debug.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try CustomInitBuildValidator.validate(rootPath: rootURL.path(percentEncoded: false))

        #expect(result.issues.count == 1)
        #expect(result.issues.first?.code == "container.custom-init-unsupported")
        #expect(result.issues.first?.metadata["containerPath"] == "AppContainer")
    }

    @Test("Semantic resolver expands top-level aliases and unique suffix matches conservatively")
    func semanticResolverExpandsAliasesAndSuffixes() {
        let resolver = SemanticResolverIndex(
            nominalTypes: [
                SemanticNominalTypeRecord(path: "Feature.AppContainer", components: ["Feature", "AppContainer"]),
                SemanticNominalTypeRecord(path: "Admin.AppContainer", components: ["Admin", "AppContainer"]),
                SemanticNominalTypeRecord(path: "Feature.Nested.AppContainer", components: ["Feature", "Nested", "AppContainer"])
            ],
            topLevelTypeAliases: [
                SemanticTypeAliasRecord(
                    path: "ActiveContainer",
                    components: ["ActiveContainer"],
                    target: SemanticTypeReference(
                        displayPath: "Feature.AppContainer",
                        components: ["Feature", "AppContainer"]
                    )
                ),
                SemanticTypeAliasRecord(
                    path: "Aliases.Active",
                    components: ["Aliases", "Active"],
                    target: SemanticTypeReference(
                        displayPath: "Feature.Nested.AppContainer",
                        components: ["Feature", "Nested", "AppContainer"]
                    )
                ),
                SemanticTypeAliasRecord(
                    path: "NestedAlias",
                    components: ["NestedAlias"],
                    target: SemanticTypeReference(
                        displayPath: "Aliases.Active",
                        components: ["Aliases", "Active"]
                    )
                )
            ]
        )

        let aliasResolved = resolver.resolvePath(
            for: SemanticTypeReference(displayPath: "ActiveContainer", components: ["ActiveContainer"]),
            candidatePaths: ["Feature.AppContainer"]
        )
        let suffixResolved = resolver.resolvePath(
            for: SemanticTypeReference(
                displayPath: "PreviewModule.Feature.AppContainer",
                components: ["PreviewModule", "Feature", "AppContainer"]
            ),
            candidatePaths: ["Feature.AppContainer"]
        )
        let ambiguousSuffix = resolver.resolvePath(
            for: SemanticTypeReference(displayPath: "AppContainer", components: ["AppContainer"]),
            candidatePaths: ["Feature.AppContainer", "Admin.AppContainer"]
        )
        let nestedAliasResolved = resolver.resolvePath(
            for: SemanticTypeReference(displayPath: "NestedAlias", components: ["NestedAlias"]),
            candidatePaths: ["Feature.Nested.AppContainer"]
        )
        let shortReverseSuffix = resolver.resolvePath(
            for: SemanticTypeReference(
                displayPath: "PreviewModule.AppContainer",
                components: ["PreviewModule", "AppContainer"]
            ),
            candidatePaths: ["AppContainer"]
        )

        #expect(aliasResolved.state == .resolved)
        #expect(aliasResolved.resolvedPath == "Feature.AppContainer")
        #expect(aliasResolved.aliasExpansionTrace == ["ActiveContainer"])
        #expect(suffixResolved.state == .resolved)
        #expect(suffixResolved.resolvedPath == "Feature.AppContainer")
        #expect(suffixResolved.usedSuffixFallback == true)
        #expect(ambiguousSuffix.state == .ambiguous)
        #expect(ambiguousSuffix.candidates == ["Admin.AppContainer", "Feature.AppContainer"])
        #expect(nestedAliasResolved.state == .resolved)
        #expect(nestedAliasResolved.resolvedPath == "Feature.Nested.AppContainer")
        #expect(nestedAliasResolved.aliasExpansionTrace == ["NestedAlias", "Aliases.Active"])
        #expect(shortReverseSuffix.state == .unresolved)
    }
}
