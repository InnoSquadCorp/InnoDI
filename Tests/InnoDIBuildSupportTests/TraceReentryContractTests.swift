import Foundation
import InnoDITestSupport
import Testing

@Suite("Trace callback reentry contracts", .serialized, .tags(.slow))
struct TraceReentryContractTests {
    @Test("Trace callbacks never hold the cell lock and same-cell reentry diagnoses promptly")
    func callbackReentry() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("innodi-trace-reentry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Probe.swift")
        try Self.probe.write(to: source, atomically: true, encoding: .utf8)
        let executable = directory.appendingPathComponent("probe")
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        compiler.arguments = ["swiftc", "-parse-as-library", "-swift-version", "6",
            "-strict-concurrency=complete", "-warnings-as-errors",
            packageRootURL().appendingPathComponent("Sources/InnoDI/DITracing.swift").path,
            packageRootURL().appendingPathComponent("Sources/InnoDI/OnDemandSharedCell.swift").path,
            source.path, "-o", executable.path]
        let build = try runCapturedProcess(compiler, timeoutSeconds: 120)
        try #require(!build.timedOut && build.exitCode == 0, "\(build.stderr)")

        for event in ["start", "waitStart", "waitEnd", "success", "cacheHit"] {
            for sameCell in [false, true] {
                let process = Process()
                process.executableURL = executable
                process.arguments = [event, sameCell ? "same" : "other"]
                var environment = ProcessInfo.processInfo.environment
                environment["SWIFT_BACKTRACE"] = "enable=no"
                process.environment = environment
                let result = try runCapturedProcess(process, timeoutSeconds: 10)
                #expect(!result.timedOut, "\(event), sameCell=\(sameCell)")
                if sameCell {
                    #expect(result.exitCode != 0)
                    #expect(result.stderr.contains("Reentrant on-demand provider resolution detected: 'value'"),
                            "\(event): \(result.stderr)")
                } else {
                    #expect(result.exitCode == 0, "\(event): \(result.stderr)")
                    #expect(result.stdout.contains("PASS"))
                }
            }
        }
    }

    private static let probe = #"""
    import Foundation
    import Dispatch
    func _innoDITrap<T>(_ message: String) -> T { fatalError(message) }

    final class Sink: DITraceSink, @unchecked Sendable {
        let kind: DITraceEvent.Kind
        let release: DispatchSemaphore
        private let lock = NSLock()
        private var callback: (@Sendable () -> Void)?
        init(_ kind: DITraceEvent.Kind, release: DispatchSemaphore) {
            self.kind = kind; self.release = release
        }
        func install(_ callback: @escaping @Sendable () -> Void) {
            lock.lock(); self.callback = callback; lock.unlock()
        }
        func record(_ event: DITraceEvent) {
            // Complete the factory while waitStart's callback is executing.
            // A lost wakeup or callback-held cell lock cannot pass this control.
            if event.kind == .waitStart { release.signal() }
            guard event.kind == kind else { return }
            lock.lock(); let action = callback; callback = nil; lock.unlock()
            action?()
        }
    }

    @main struct Probe {
        static func main() {
            let kind = DITraceEvent.Kind(rawValue: CommandLine.arguments[1])!
            let release = DispatchSemaphore(value: 0)
            let started = DispatchSemaphore(value: 0)
            let done = DispatchGroup()
            let sink = Sink(kind, release: release)
            let owner = _InnoDITraceOwner(context: DITraceContext(sink: sink), containerType: Probe.self)
            let waiting = kind == .waitStart || kind == .waitEnd
            let cell = _InnoDISendableSharedCell(traceOwner: owner, providerName: "value", factory: {
                started.signal()
                if waiting { precondition(release.wait(timeout: .now() + 3) == .success) }
                return 7
            })
            if CommandLine.arguments[2] == "same" {
                sink.install { _ = cell.value() }
            } else {
                let other = _InnoDISendableSharedCell(traceOwner: .disabled, providerName: "other", value: 9)
                sink.install { precondition(other.value() == 9) }
            }
            done.enter()
            DispatchQueue.global().async { precondition(cell.value() == 7); done.leave() }
            if waiting {
                precondition(started.wait(timeout: .now() + 3) == .success)
                done.enter()
                DispatchQueue.global().async { precondition(cell.value() == 7); done.leave() }
            }
            precondition(done.wait(timeout: .now() + 3) == .success, "callback deadlocked")
            if kind == .cacheHit { precondition(cell.value() == 7) }
            print("PASS")
        }
    }
    """#
}
