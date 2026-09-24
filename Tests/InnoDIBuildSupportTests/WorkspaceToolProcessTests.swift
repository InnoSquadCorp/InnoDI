import Darwin
import Foundation
import InnoDIWorkspaceAnalysis
import Testing

@Suite("Bounded workspace tool processes", .serialized)
struct WorkspaceToolProcessTests {
    @Test("Closed standard descriptors preserve separate and merged child streams")
    func closedStandardDescriptors() throws {
        // Closing descriptors in this test process would corrupt parallel suites.
        // Compile the actual runner into a dedicated, disposable child instead.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("innodi-closed-fds-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Probe.swift")
        try #"""
        import Darwin
        import Foundation
        @main struct Probe {
            static func main() throws {
                let mask = Int(CommandLine.arguments[1])!
                let merged = CommandLine.arguments[2] == "true"
                let reportURL = URL(fileURLWithPath: CommandLine.arguments[3])
                let environment = ProcessInfo.processInfo.environment
                for fd: Int32 in 0...2 where mask & (1 << fd) != 0 { _ = Darwin.close(fd) }
                var report: [String: Any] = [:]
                do {
                    let result = try runWorkspaceTool(executable: "/bin/sh",
                        arguments: ["-c", "set -e; printf OUT; printf ERR >&2"],
                        environment: environment, timeout: 2, mergeOutput: merged)
                    report = ["exit": result.exitCode, "stdout": result.stdout,
                              "stderr": result.stderr, "timedOut": result.timedOut]
                } catch {
                    report = ["error": String(describing: error)]
                }
                try JSONSerialization.data(withJSONObject: report).write(to: reportURL)
            }
        }
        """#.write(to: source, atomically: true, encoding: .utf8)
        let executable = root.appendingPathComponent("probe")
        let compilation = try runWorkspaceTool(executable: "/usr/bin/xcrun", arguments: [
            "swiftc", "-swift-version", "6", "-strict-concurrency=complete", "-warnings-as-errors",
            "-package-name", "InnoDIProbe",
            packageRootURL().appendingPathComponent("Sources/InnoDIWorkspaceAnalysis/WorkspaceToolProcess.swift").path,
            source.path, "-o", executable.path,
        ], timeout: 60)
        try #require(compilation.exitCode == 0, "\(compilation.stderr)")
        for mask in 0...7 {
            for merged in [false, true] {
                let reportURL = root.appendingPathComponent("\(mask)-\(merged).json")
                let child = try runWorkspaceTool(executable: executable.path,
                    arguments: [String(mask), String(merged), reportURL.path], timeout: 5)
                try #require(child.exitCode == 0, "mask=\(mask) merged=\(merged): \(child.stderr)")
                let report = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: reportURL)) as? [String: Any])
                #expect(report["error"] == nil, "mask=\(mask) merged=\(merged): \(report)")
                #expect(report["exit"] as? Int == 0)
                #expect(report["timedOut"] as? Bool == false)
                #expect(report["stdout"] as? String == (merged ? "OUTERR" : "OUT"))
                #expect(report["stderr"] as? String == (merged ? "" : "ERR"))
            }
        }
    }

    @Test("Both output streams drain with bounded tails and a nonzero exit")
    func boundedStreams() throws {
        let result = try runWorkspaceTool(
            executable: "/bin/sh",
            arguments: ["-c", "i=0; while [ $i -lt 20000 ]; do printf 'abcdefghijklmnopqrstuvwxyz0123456789\\n'; printf 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\\n' >&2; i=$((i + 1)); done; printf OUTEND; printf ERREND >&2; exit 7"],
            timeout: 10, captureLimit: 1_024
        )
        #expect(result.exitCode == 7)
        #expect(!result.timedOut)
        #expect(result.outputTruncated)
        #expect(result.stdout.utf8.count <= 1_024)
        #expect(result.stderr.utf8.count <= 1_024)
        #expect(result.stdout.hasSuffix("OUTEND"))
        #expect(result.stderr.hasSuffix("ERREND"))
    }

    @Test("Continuous output cannot starve the timeout or signal unrelated processes")
    func noisyTimeout() throws {
        let control = Process()
        control.executableURL = URL(fileURLWithPath: "/bin/sleep")
        control.arguments = ["10"]
        try control.run()
        defer { control.terminate(); control.waitUntilExit() }
        let result = try runWorkspaceTool(
            executable: "/bin/sh", arguments: ["-c", "trap '' TERM; while :; do printf 0123456789; done"],
            timeout: 0.1, captureLimit: 512
        )
        #expect(result.timedOut)
        #expect(result.exitCode == 128 + SIGKILL)
        #expect(result.stdout.utf8.count <= 512)
        #expect(result.outputTruncated)
        #expect(control.isRunning)
    }

    @Test("Arguments, working directory and explicit environment are preserved")
    func invocationControl() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let result = try runWorkspaceTool(executable: "/bin/sh",
            arguments: ["-c", "printf '%s|%s|%s' \"$PWD\" \"$VALUE\" \"$1\"", "fixture", "a;$(false) b"],
            directory: root, environment: ["VALUE": "isolated"], timeout: 2)
        #expect(result.exitCode == 0)
        #expect(!result.outputTruncated)
        let fields = result.stdout.components(separatedBy: "|")
        #expect(fields.count == 3)
        #expect(URL(fileURLWithPath: fields[0]).resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path)
        #expect(fields.dropFirst() == ["isolated", "a;$(false) b"])
    }

    @Test("Missing executable and directory fail without orphaned processes")
    func spawnFailure() {
        #expect(throws: (any Error).self) {
            _ = try runWorkspaceTool(executable: "/innodi-nonexistent-\(UUID())", arguments: [])
        }
        #expect(throws: (any Error).self) {
            _ = try runWorkspaceTool(executable: "/bin/true", arguments: [],
                                     directory: URL(fileURLWithPath: "/innodi-nonexistent-\(UUID())"))
        }
    }
}
