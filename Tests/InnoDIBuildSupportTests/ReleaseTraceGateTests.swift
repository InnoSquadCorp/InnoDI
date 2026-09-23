import Foundation
import Testing

@Suite("SHA-bound release trace gate")
struct ReleaseTraceGateTests {
    private func workflow() throws -> String {
        try String(contentsOf: packageRootURL().appendingPathComponent(".github/workflows/release.yml"), encoding: .utf8)
    }

    private func section(_ source: String, from: String, to: String) -> String? {
        guard let start = source.range(of: from),
              let end = source.range(of: to, range: start.upperBound..<source.endIndex) else { return nil }
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func enforcesTrace(_ source: String) -> Bool {
        guard let job = section(source, from: "  release-gate:", to: "  release-compatibility:"),
              let step = section(job, from: "      - name: Enforce candidate runtime trace performance",
                                 to: "      - name: Upload runtime trace diagnostics"),
              let upload = section(job, from: "      - name: Upload runtime trace diagnostics",
                                   to: "      - name: Generate release artifacts"),
              let staging = section(source, from: "  stage-release:", to: "    steps:") else { return false }
        return job.contains("ref: ${{ inputs.commit_sha }}")
            && !job.contains("continue-on-error:")
            && !step.contains("if:")
            && !step.contains("||")
            && step.contains("INNODI_RUNTIME_TRACE_EXPECTED_SHA: ${{ inputs.commit_sha }}")
            && step.contains("INNODI_RUNTIME_TRACE_REPORT: build/release-runtime-trace-performance-report.json")
            && step.contains("        run: Tools/measure-runtime-trace-performance.sh\n")
            && upload.contains("name: release-runtime-trace-${{ inputs.commit_sha }}")
            && upload.contains("path: build/release-runtime-trace-performance-report.json")
            && upload.contains("if-no-files-found: error")
            && staging.contains("      - release-gate\n")
            && !staging.contains("if:")
    }

    @Test("Staging requires successful candidate trace evidence and retains its diagnostics")
    func workflowContract() throws {
        let source = try workflow()
        #expect(enforcesTrace(source))
        let mutations: [(String, String)] = [
            ("run: Tools/measure-runtime-trace-performance.sh", "run: true"),
            ("run: Tools/measure-runtime-trace-performance.sh", "run: Tools/measure-runtime-trace-performance.sh || true"),
            ("INNODI_RUNTIME_TRACE_EXPECTED_SHA: ${{ inputs.commit_sha }}", "INNODI_RUNTIME_TRACE_EXPECTED_SHA: main"),
            ("      - name: Enforce candidate runtime trace performance", "      - name: Enforce candidate runtime trace performance\n        if: false"),
            ("      - name: Enforce candidate runtime trace performance", "      - name: Enforce candidate runtime trace performance\n        continue-on-error: true"),
            ("name: release-runtime-trace-${{ inputs.commit_sha }}", "name: unrelated-report"),
            ("      - release-gate\n", ""),
        ]
        for (old, new) in mutations {
            #expect(!enforcesTrace(source.replacingOccurrences(of: old, with: new)), "Failed to reject \(new)")
        }
    }

    @Test("Wrong candidate SHA fails before compiling the benchmark")
    func wrongCandidatePreflight() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["Tools/measure-runtime-trace-performance.sh"]
        process.currentDirectoryURL = packageRootURL()
        var environment = ProcessInfo.processInfo.environment
        environment["INNODI_RUNTIME_TRACE_EXPECTED_SHA"] = String(repeating: "0", count: 40)
        process.environment = environment
        let error = Pipe()
        process.standardError = error
        try process.run()
        let message = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus != 0)
        #expect(String(decoding: message, as: UTF8.self).contains("clean checkout of the exact candidate SHA"))
    }
}
