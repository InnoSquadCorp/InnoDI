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
/// On timeout the runner first requests graceful termination, then sends
/// `SIGKILL` after the grace period. It intentionally skips a blocking final
/// pipe drain on that path because descendants may still hold inherited pipe
/// descriptors open.
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
    if timedOut, process.isRunning {
        process.terminate()
        if !waitForTermination(
            terminationSemaphore,
            timeoutSeconds: terminationGraceSeconds
        ), process.isRunning {
            _ = kill(process.processIdentifier, SIGKILL)
            _ = waitForTermination(
                terminationSemaphore,
                timeoutSeconds: hardKillGraceSeconds
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
    semaphore.wait(timeout: .now() + timeoutSeconds) == .success
}
