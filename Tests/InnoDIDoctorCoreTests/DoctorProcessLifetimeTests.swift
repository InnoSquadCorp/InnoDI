import Darwin
import Foundation
import Testing
@testable import InnoDIDoctorCore

@Suite("Doctor verification process lifetime", .serialized)
struct DoctorProcessLifetimeTests {
    @Test("Verification completion and timeout terminate owned child processes", arguments: [false, true])
    func completionOwnsChildren(timedOut: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("innodi-process-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let pidFile = root.appendingPathComponent("child.pid")
        let result = try runVerificationStep(
            arguments: ["/bin/sh", "-c", "trap '' TERM; sleep 30 & echo $! > \"$1\"; " + (timedOut ? "wait" : "exit 0"), "fixture", pidFile.path],
            command: "owned timeout fixture", root: root, environment: nil, timeout: 0.2
        )
        let child = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        // Only this fixture's child is cleaned up on the failing baseline.
        var needsCleanup = true
        defer { if needsCleanup { _ = kill(child, SIGKILL) } }
        #expect(result.timedOut == timedOut)
        #expect(result.status == (timedOut ? .failed : .passed))
        let deadline = Date().addingTimeInterval(1)
        while kill(child, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        needsCleanup = kill(child, 0) == 0
        #expect(!needsCleanup)
    }

    @Test("Successful verification preserves output and status")
    func successControl() throws {
        let result = try runVerificationStep(arguments: ["/bin/echo", "ready"], command: "echo",
                                             root: FileManager.default.temporaryDirectory, environment: nil, timeout: 2)
        #expect(result.status == .passed)
        #expect(result.timedOut == false)
        #expect(result.outputTail == "ready\n")
    }

    @Test("Doctor reports truncation without retaining an unbounded log")
    func truncatedLog() throws {
        let result = try runVerificationStep(
            arguments: ["/bin/sh", "-c", "i=0; while [ $i -lt 5000 ]; do printf abcdefghijklmnopqrstuvwxyz; i=$((i + 1)); done; printf END"],
            command: "bounded log fixture", root: FileManager.default.temporaryDirectory, environment: nil, timeout: 5
        )
        let tail = try #require(result.outputTail)
        #expect(result.status == .passed)
        #expect(tail.hasPrefix("[output truncated]"))
        #expect(tail.utf8.count <= 16_384)
        #expect(tail.hasSuffix("END"))
    }
}
