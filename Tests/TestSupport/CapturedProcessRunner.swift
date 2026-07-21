import Dispatch
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Captured output and termination state for a test-owned subprocess.
public struct CapturedProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public var combinedOutput: String {
        [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    public init(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        timedOut: Bool
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

/// Runs a subprocess while draining stdout and stderr concurrently.
///
/// On timeout the runner snapshots the subprocess tree, requests graceful
/// termination from descendants before their parent, then sends `SIGKILL` to
/// survivors after the grace period. It intentionally skips a blocking final
/// pipe drain on that path because an unobservable descendant may still hold
/// an inherited pipe descriptor open.
public func runCapturedProcess(
    _ process: Process,
    timeoutSeconds: TimeInterval,
    terminationGraceSeconds: TimeInterval = 5,
    hardKillGraceSeconds: TimeInterval = 2
) throws -> CapturedProcessResult {
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let stdoutSink = CapturedProcessDataSink()
    let stderrSink = CapturedProcessDataSink()
    installReadHandler(on: stdoutPipe.fileHandleForReading, sink: stdoutSink)
    installReadHandler(on: stderrPipe.fileHandleForReading, sink: stderrSink)

    let terminationSemaphore = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in
        terminationSemaphore.signal()
    }

    try process.run()
    let timedOut = !waitForTermination(
        terminationSemaphore,
        timeoutSeconds: timeoutSeconds
    )
    if timedOut {
        var processTree = CapturedProcessTree(
            rootProcessID: process.processIdentifier
        )
        processTree.sendToDescendants(SIGTERM)
        if process.isRunning {
            process.terminate()
        }

        let gracefulDeadline = capturedProcessDeadline(
            after: terminationGraceSeconds
        )
        if process.isRunning {
            _ = waitForTermination(
                terminationSemaphore,
                deadline: gracefulDeadline
            )
        }
        _ = processTree.waitForDescendantsToExit(
            deadline: gracefulDeadline
        )

        processTree.refresh()
        if process.isRunning || processTree.hasRunningDescendants {
            processTree.sendToDescendants(SIGKILL)
            if process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
            }
            let hardKillDeadline = capturedProcessDeadline(
                after: hardKillGraceSeconds
            )
            if process.isRunning {
                _ = waitForTermination(
                    terminationSemaphore,
                    deadline: hardKillDeadline
                )
            }
            _ = processTree.waitForDescendantsToExit(
                deadline: hardKillDeadline
            )
        }
    }

    let stdoutHandle = stdoutPipe.fileHandleForReading
    let stderrHandle = stderrPipe.fileHandleForReading
    stdoutHandle.readabilityHandler = nil
    stderrHandle.readabilityHandler = nil
    if !timedOut {
        stdoutSink.append(stdoutHandle.readDataToEndOfFile())
        stderrSink.append(stderrHandle.readDataToEndOfFile())
    }
    stdoutHandle.closeFile()
    stderrHandle.closeFile()

    return CapturedProcessResult(
        exitCode: process.isRunning ? Int32(SIGKILL) : process.terminationStatus,
        stdout: String(decoding: stdoutSink.snapshot(), as: UTF8.self),
        stderr: String(decoding: stderrSink.snapshot(), as: UTF8.self),
        timedOut: timedOut
    )
}

private final class CapturedProcessDataSink: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

private func installReadHandler(
    on handle: FileHandle,
    sink: CapturedProcessDataSink
) {
    handle.readabilityHandler = { readableHandle in
        let data = readableHandle.availableData
        if data.isEmpty {
            readableHandle.readabilityHandler = nil
            return
        }
        sink.append(data)
    }
}

private func waitForTermination(
    _ semaphore: DispatchSemaphore,
    timeoutSeconds: TimeInterval
) -> Bool {
    waitForTermination(
        semaphore,
        deadline: capturedProcessDeadline(after: timeoutSeconds)
    )
}

private func waitForTermination(
    _ semaphore: DispatchSemaphore,
    deadline: DispatchTime
) -> Bool {
    semaphore.wait(timeout: deadline) == .success
}
