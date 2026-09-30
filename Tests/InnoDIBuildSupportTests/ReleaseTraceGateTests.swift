import Foundation
import Testing

@Suite("Optional trace diagnostics and required release gates")
struct ReleaseTraceGateTests {
    private func workflow() throws -> String {
        try String(contentsOf: packageRootURL().appendingPathComponent(".github/workflows/release.yml"), encoding: .utf8)
    }

    private func section(_ source: String, from: String, to: String) -> String? {
        guard let start = source.range(of: from),
              let end = source.range(of: to, range: start.upperBound..<source.endIndex) else { return nil }
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func preservesReleasePolicy(_ source: String) -> Bool {
        guard let job = section(source, from: "  release-gate:", to: "  release-compatibility:"),
              let macro = section(job, from: "      - name: Enforce macro performance baseline",
                                  to: "      - name: Upload candidate macro performance report"),
              let staging = section(source, from: "  stage-release:", to: "    steps:") else { return false }
        return job.contains("ref: ${{ inputs.commit_sha }}")
            && !job.contains("continue-on-error:")
            && !source.contains("Tools/measure-runtime-trace-performance.sh")
            && !source.contains("uses: ./.github/workflows/runtime-trace-diagnostics.yml")
            // Trace timing policy must not weaken the separate macro gate.
            && !macro.contains("if:")
            && !macro.contains("||")
            && macro.contains("        id: macro_performance\n")
            && macro.contains("        run: Tools/measure-macro-performance.sh --enforce --output build/release-macro-performance-report.json\n")
            && staging.contains("      - release-gate\n")
            && staging.contains("    if: inputs.publish\n")
            && staging.components(separatedBy: "if:").count - 1 == 1
    }

    @Test("Staging preserves required gates without requiring trace timing evidence")
    func workflowContract() throws {
        let source = try workflow()
        #expect(preservesReleasePolicy(source))
        let mutations: [(String, String)] = [
            ("      - name: Generate release artifacts", "      - name: Trace gate\n        run: Tools/measure-runtime-trace-performance.sh\n      - name: Generate release artifacts"),
            ("run: Tools/measure-macro-performance.sh --enforce", "run: Tools/measure-macro-performance.sh --report-only"),
            ("run: Tools/measure-macro-performance.sh --enforce --output build/release-macro-performance-report.json", "run: Tools/measure-macro-performance.sh --enforce --output build/release-macro-performance-report.json || true"),
            ("ref: ${{ inputs.commit_sha }}", "ref: main"),
            ("      - name: Enforce macro performance baseline", "      - name: Enforce macro performance baseline\n        if: false"),
            ("      - name: Enforce macro performance baseline", "      - name: Enforce macro performance baseline\n        continue-on-error: true"),
            ("        id: macro_performance\n", ""),
            ("      - release-gate\n", ""),
            ("    if: inputs.publish\n", "    if: false\n"),
        ]
        for (old, new) in mutations {
            #expect(source.contains(old), "Mutation must apply: \(old)")
            #expect(!preservesReleasePolicy(source.replacingOccurrences(of: old, with: new)), "Failed to reject \(new)")
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
