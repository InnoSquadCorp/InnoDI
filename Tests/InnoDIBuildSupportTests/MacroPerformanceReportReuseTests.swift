import Foundation
import Testing

@Suite("Macro performance report reuse contracts")
struct MacroPerformanceReportReuseTests {
    @Test("Report validator accepts internally consistent measurements")
    func validatorAcceptsValidReport() throws {
        let fixture = try MacroPerformanceReportReuseFixture()
        defer { fixture.remove() }

        let result = try fixture.validate(report: fixture.validReportURL)

        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("Validated macro performance report"))
    }

    @Test("Report validator rejects statistics that do not match samples")
    func validatorRejectsInconsistentStatistics() throws {
        let fixture = try MacroPerformanceReportReuseFixture()
        defer { fixture.remove() }

        let result = try fixture.validate(report: fixture.invalidReportURL)

        #expect(result.exitCode == 1)
        #expect(result.output.contains("mean_ms does not match samples_ms"))
    }

    @Test("Trend check reuses an existing report without invoking Swift")
    func trendCheckReusesReport() throws {
        let fixture = try MacroPerformanceReportReuseFixture()
        defer { fixture.remove() }

        let result = try fixture.runTrendCheck()

        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("reusing macro performance report"))
        #expect(result.output.contains("perf-history branch unreachable"))
        #expect(!FileManager.default.fileExists(atPath: fixture.swiftMarkerURL.path))
    }

    @Test("History append rejects an invalid reused report before reading commit metadata")
    func historyAppendRejectsInvalidReportEarly() throws {
        let fixture = try MacroPerformanceReportReuseFixture()
        defer { fixture.remove() }

        let result = try fixture.runHistoryAppendWithInvalidReport()

        #expect(result.exitCode == 1)
        #expect(result.output.contains("mean_ms does not match samples_ms"))
        #expect(!FileManager.default.fileExists(atPath: fixture.gitMetadataMarkerURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.swiftMarkerURL.path))
    }

    @Test("Performance history is indexed by commit time rather than SHA")
    func historyIndexUsesCommitTime() throws {
        let script = try String(
            contentsOf: packageRootURL()
                .appendingPathComponent("Tools/append-performance-history.sh"),
            encoding: .utf8
        )

        #expect(
            script.contains(
                #"entries.sort(key=lambda entry: (entry.get("commit_at") or "", entry["path"]))"#
            )
        )
    }
}

private struct MacroPerformanceReportReuseResult {
    let exitCode: Int32
    let output: String
}

private struct MacroPerformanceReportReuseFixture {
    let rootURL: URL
    let fakeBinURL: URL
    let validReportURL: URL
    let invalidReportURL: URL
    let swiftMarkerURL: URL
    let gitMetadataMarkerURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "InnoDI-MacroPerformanceReportReuse-\(UUID().uuidString)",
            isDirectory: true
        )
        fakeBinURL = rootURL.appendingPathComponent("bin", isDirectory: true)
        validReportURL = rootURL.appendingPathComponent("valid.json")
        invalidReportURL = rootURL.appendingPathComponent("invalid.json")
        swiftMarkerURL = rootURL.appendingPathComponent("swift.marker")
        gitMetadataMarkerURL = rootURL.appendingPathComponent("git-metadata.marker")
        try FileManager.default.createDirectory(
            at: fakeBinURL,
            withIntermediateDirectories: true
        )

        try Self.report(meanMS: 11.0).write(
            to: validReportURL,
            atomically: true,
            encoding: .utf8
        )
        try Self.report(meanMS: 99.0).write(
            to: invalidReportURL,
            atomically: true,
            encoding: .utf8
        )

        try writeExecutable(
            named: "swift",
            contents: """
            #!/bin/bash
            touch "${FAKE_SWIFT_MARKER:?}"
            exit 70
            """
        )
        try writeExecutable(
            named: "git",
            contents: """
            #!/bin/bash
            if [[ "${1:-}" == "fetch" ]]; then
              exit 1
            fi
            if [[ "${1:-}" == "rev-parse" && "${2:-}" == "--git-dir" ]]; then
              printf '.git\\n'
              exit 0
            fi
            touch "${FAKE_GIT_METADATA_MARKER:?}"
            exit 71
            """
        )
    }

    func validate(report: URL) throws -> MacroPerformanceReportReuseResult {
        try run(
            executable: "/usr/bin/python3",
            arguments: [
                packageRootURL()
                    .appendingPathComponent("Tools/validate-macro-performance-report.py")
                    .path,
                report.path,
            ],
            useFakePath: false
        )
    }

    func runTrendCheck() throws -> MacroPerformanceReportReuseResult {
        try run(
            executable: "/bin/bash",
            arguments: [
                packageRootURL()
                    .appendingPathComponent("Tools/check-performance-trend.sh")
                    .path,
                "--current-report",
                validReportURL.path,
            ],
            useFakePath: true
        )
    }

    func runHistoryAppendWithInvalidReport() throws -> MacroPerformanceReportReuseResult {
        try run(
            executable: "/bin/bash",
            arguments: [
                packageRootURL()
                    .appendingPathComponent("Tools/append-performance-history.sh")
                    .path,
                "--report",
                invalidReportURL.path,
            ],
            useFakePath: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static func report(meanMS: Double) -> String {
        """
        {
          "updated_at": "2026-07-17T00:00:00Z",
          "swift_version": "Apple Swift version 6.3.3",
          "mode": "in-process",
          "filter": "MacroPerformanceBenchmark",
          "iterations": 2,
          "mean_ms": \(meanMS),
          "median_ms": 11.0,
          "min_ms": 10.0,
          "max_ms": 12.0,
          "stdev_ms": 1.414,
          "samples_ms": [10.0, 12.0]
        }
        """
    }

    private func writeExecutable(named name: String, contents: String) throws {
        let url = fakeBinURL.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private func run(
        executable: String,
        arguments: [String],
        useFakePath: Bool
    ) throws -> MacroPerformanceReportReuseResult {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output

        var environment = ProcessInfo.processInfo.environment
        if useFakePath {
            environment["PATH"] = fakeBinURL.path + ":/usr/bin:/bin"
        }
        environment["FAKE_SWIFT_MARKER"] = swiftMarkerURL.path
        environment["FAKE_GIT_METADATA_MARKER"] = gitMetadataMarkerURL.path
        process.environment = environment

        try process.run()
        process.waitUntilExit()

        return MacroPerformanceReportReuseResult(
            exitCode: process.terminationStatus,
            output: String(
                decoding: output.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
        )
    }
}
