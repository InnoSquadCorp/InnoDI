import Foundation
import Testing

@Suite("Macro performance script contracts")
struct MacroPerformanceScriptTests {
    private let fakeSwiftVersion =
        "Apple Swift version 6.3 (swiftlang-test clang-test)"

    @Test("Explicit enforcement rejects a missing baseline before measurement")
    func enforceRejectsMissingBaseline() throws {
        let fixture = try MacroPerformanceScriptFixture(
            swiftVersion: fakeSwiftVersion
        )
        defer { fixture.remove() }

        let result = try fixture.run(
            arguments: [
                "--iterations", "2",
                "--baseline", fixture.baselineURL.path,
                "--enforce",
            ]
        )

        #expect(result.exitCode != 0)
        #expect(result.output.contains("baseline missing"))
        #expect(!fixture.measurementWasInvoked)
        #expect(!FileManager.default.fileExists(atPath: fixture.baselineURL.path))
    }

    @Test("GitHub Actions enforcement rejects a missing baseline")
    func githubActionsRejectsMissingBaseline() throws {
        let fixture = try MacroPerformanceScriptFixture(
            swiftVersion: fakeSwiftVersion
        )
        defer { fixture.remove() }

        let result = try fixture.run(
            arguments: [
                "--iterations", "2",
                "--baseline", fixture.baselineURL.path,
            ],
            additionalEnvironment: ["GITHUB_ACTIONS": "true"]
        )

        #expect(result.exitCode != 0)
        #expect(result.output.contains("baseline missing"))
        #expect(!fixture.measurementWasInvoked)
    }

    @Test("Enforcement rejects a mismatched Swift baseline before measurement")
    func enforceRejectsSwiftVersionMismatch() throws {
        let fixture = try MacroPerformanceScriptFixture(
            swiftVersion: fakeSwiftVersion
        )
        defer { fixture.remove() }
        try fixture.writeBaseline(
            swiftVersion: "Apple Swift version 6.2 (swiftlang-old clang-old)"
        )

        let result = try fixture.run(
            arguments: [
                "--iterations", "2",
                "--baseline", fixture.baselineURL.path,
                "--enforce",
            ]
        )

        #expect(result.exitCode != 0)
        #expect(result.output.contains("baseline swift version mismatch"))
        #expect(!fixture.measurementWasInvoked)
    }

    @Test("Enforcement rejects a baseline without Swift identity")
    func enforceRejectsMissingSwiftVersion() throws {
        let fixture = try MacroPerformanceScriptFixture(
            swiftVersion: fakeSwiftVersion
        )
        defer { fixture.remove() }
        try fixture.writeBaseline(swiftVersion: nil)

        let result = try fixture.run(
            arguments: [
                "--iterations", "2",
                "--baseline", fixture.baselineURL.path,
                "--enforce",
            ]
        )

        #expect(result.exitCode != 0)
        #expect(result.output.contains("baseline swift_version missing"))
        #expect(!fixture.measurementWasInvoked)
    }

    @Test("Enforcement rejects a non-positive baseline minimum before measurement")
    func enforceRejectsZeroBaselineMinimum() throws {
        let fixture = try MacroPerformanceScriptFixture(
            swiftVersion: fakeSwiftVersion
        )
        defer { fixture.remove() }
        try fixture.writeBaseline(swiftVersion: fakeSwiftVersion, minMS: "0")

        let result = try fixture.run(
            arguments: [
                "--iterations", "2",
                "--baseline", fixture.baselineURL.path,
                "--enforce",
            ]
        )

        #expect(result.exitCode != 0)
        #expect(result.output.contains("baseline min_ms must be a finite positive number"))
        #expect(!fixture.measurementWasInvoked)
    }

    @Test("Explicit baseline update writes validated measurements")
    func updateBaselineWritesValidatedMeasurement() throws {
        let fixture = try MacroPerformanceScriptFixture(
            swiftVersion: fakeSwiftVersion,
            reportJSON: """
                {
                  "iterations": 2,
                  "samples_ms": [11.0, 12.0]
                }
                """
        )
        defer { fixture.remove() }
        try Data().write(to: fixture.baselineURL)

        let result = try fixture.run(
            arguments: [
                "--iterations", "2",
                "--baseline", fixture.baselineURL.path,
                "--update-baseline",
            ]
        )

        #expect(result.exitCode == 0)
        #expect(result.output.contains("baseline updated"))
        #expect(fixture.measurementWasInvoked)

        let data = try Data(contentsOf: fixture.baselineURL)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["swift_version"] as? String == fakeSwiftVersion)
        #expect(object["iterations"] as? Int == 2)
        #expect(object["mean_ms"] as? Double == 11.5)
        #expect(object["median_ms"] as? Double == 11.5)
        #expect((object["samples_ms"] as? [Any])?.count == 2)
    }

    @Test("Explicit output writes a reusable report without mutating the baseline")
    func outputWritesReusableReport() throws {
        let fixture = try MacroPerformanceScriptFixture(
            swiftVersion: fakeSwiftVersion
        )
        defer { fixture.remove() }
        try fixture.writeBaseline(swiftVersion: fakeSwiftVersion)
        let originalBaseline = try Data(contentsOf: fixture.baselineURL)

        let result = try fixture.run(
            arguments: [
                "--iterations", "2",
                "--baseline", fixture.baselineURL.path,
                "--output", fixture.reportURL.path,
                "--enforce",
            ]
        )

        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("report written"))
        #expect(try Data(contentsOf: fixture.baselineURL) == originalBaseline)

        let data = try Data(contentsOf: fixture.reportURL)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["swift_version"] as? String == fakeSwiftVersion)
        #expect(object["mean_ms"] as? Double == 10.0)
        #expect(object["median_ms"] as? Double == 10.0)
        #expect((object["samples_ms"] as? [Any])?.count == 2)
    }

    @Test("Enforcement ignores upward latency noise but retains its telemetry")
    func enforcementUsesLowerEnvelopeForLatencyNoise() throws {
        let fixture = try MacroPerformanceScriptFixture(
            swiftVersion: fakeSwiftVersion,
            reportJSON: """
                {
                  "iterations": 4,
                  "samples_ms": [10.0, 10.0, 10.0, 100.0]
                }
                """
        )
        defer { fixture.remove() }
        try fixture.writeBaseline(swiftVersion: fakeSwiftVersion)

        let result = try fixture.run(
            arguments: [
                "--iterations", "4",
                "--baseline", fixture.baselineURL.path,
                "--output", fixture.reportURL.path,
                "--enforce",
            ]
        )

        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("baseline min=10.0ms, current min=10.000ms"))

        let data = try Data(contentsOf: fixture.reportURL)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["median_ms"] as? Double == 10.0)
        #expect(object["mean_ms"] as? Double == 32.5)
        #expect(object["max_ms"] as? Double == 100.0)
    }

    @Test("Enforcement rejects a slowdown present in every sample")
    func enforcementRejectsConsistentSlowdown() throws {
        let fixture = try MacroPerformanceScriptFixture(
            swiftVersion: fakeSwiftVersion,
            reportJSON: """
                {
                  "iterations": 3,
                  "samples_ms": [13.0, 14.0, 15.0]
                }
                """
        )
        defer { fixture.remove() }
        try fixture.writeBaseline(swiftVersion: fakeSwiftVersion)

        let result = try fixture.run(
            arguments: [
                "--iterations", "3",
                "--baseline", fixture.baselineURL.path,
                "--enforce",
            ]
        )

        #expect(result.exitCode != 0)
        #expect(result.output.contains("current min=13.000ms, delta=30.00%"))
        #expect(result.output.contains("regression exceeded threshold (20%)"))
    }

    @Test("Invalid in-process samples never create a baseline")
    func invalidSamplesDoNotCreateBaseline() throws {
        let fixture = try MacroPerformanceScriptFixture(
            swiftVersion: fakeSwiftVersion,
            reportJSON: """
                {
                  "iterations": 2,
                  "samples_ms": [10.0]
                }
                """
        )
        defer { fixture.remove() }

        let result = try fixture.run(
            arguments: [
                "--iterations", "2",
                "--baseline", fixture.baselineURL.path,
                "--update-baseline",
            ]
        )

        #expect(result.exitCode != 0)
        #expect(result.output.contains("sample count does not match"))
        #expect(fixture.measurementWasInvoked)
        #expect(!FileManager.default.fileExists(atPath: fixture.baselineURL.path))
    }

    @Test("A failed measured subprocess never creates a baseline")
    func failedMeasuredSubprocessDoesNotCreateBaseline() throws {
        let fixture = try MacroPerformanceScriptFixture(
            swiftVersion: fakeSwiftVersion
        )
        defer { fixture.remove() }

        let result = try fixture.run(
            arguments: [
                "--subprocess",
                "--filter", "FakeMacroTests",
                "--iterations", "1",
                "--baseline", fixture.baselineURL.path,
                "--update-baseline",
            ],
            additionalEnvironment: ["FAKE_SWIFT_FAIL_TEST_INVOCATION": "2"]
        )

        #expect(result.exitCode != 0)
        #expect(result.output.contains("measured subprocess failed"))
        #expect(fixture.measurementWasInvoked)
        #expect(!FileManager.default.fileExists(atPath: fixture.baselineURL.path))
    }
}

private struct MacroPerformanceScriptResult {
    let exitCode: Int32
    let output: String
}

private struct MacroPerformanceScriptFixture {
    let rootURL: URL
    let baselineURL: URL
    let reportURL: URL
    let markerURL: URL
    let fakeBinURL: URL
    let swiftVersion: String
    let reportJSON: String

    init(
        swiftVersion: String,
        reportJSON: String = """
            {
              "iterations": 2,
              "samples_ms": [10.0, 10.0]
            }
            """
    ) throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "InnoDI-MacroPerformanceScriptTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let fakeBinURL = rootURL.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(
            at: fakeBinURL,
            withIntermediateDirectories: true
        )

        let fakeSwiftURL = fakeBinURL.appendingPathComponent("swift")
        let fakeSwift = """
            #!/usr/bin/env bash
            set -euo pipefail

            case "${1:-}" in
              --version)
                printf '%s\\n' "${FAKE_SWIFT_VERSION:?}"
                ;;
              test)
                printf 'test\\n' >> "${FAKE_SWIFT_MARKER:?}"
                INVOCATION="$(wc -l < "$FAKE_SWIFT_MARKER" | tr -d '[:space:]')"
                if [[ -n "${FAKE_SWIFT_FAIL_TEST_INVOCATION:-}" && "$INVOCATION" == "$FAKE_SWIFT_FAIL_TEST_INVOCATION" ]]; then
                  exit 42
                fi
                if [[ -n "${INNODI_MACRO_BENCH_OUTPUT:-}" ]]; then
                  printf '%s\\n' "${FAKE_SWIFT_REPORT_JSON:?}" > "$INNODI_MACRO_BENCH_OUTPUT"
                fi
                ;;
              *)
                echo "unexpected fake swift arguments: $*" >&2
                exit 64
                ;;
            esac
            """
        try fakeSwift.write(to: fakeSwiftURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeSwiftURL.path
        )

        self.rootURL = rootURL
        self.baselineURL = rootURL.appendingPathComponent("baseline.json")
        self.reportURL = rootURL.appendingPathComponent("reports/current.json")
        self.markerURL = rootURL.appendingPathComponent("measurement.marker")
        self.fakeBinURL = fakeBinURL
        self.swiftVersion = swiftVersion
        self.reportJSON = reportJSON
    }

    var measurementWasInvoked: Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
    }

    func writeBaseline(
        swiftVersion: String?,
        meanMS: String = "10.0",
        medianMS: String = "10.0",
        minMS: String = "10.0"
    ) throws {
        var entries = [
            #""updated_at": "2026-01-01T00:00:00Z""#,
        ]
        if let swiftVersion {
            entries.append(#""swift_version": "\#(swiftVersion)""#)
        }
        entries.append(contentsOf: [
            #""mode": "in-process""#,
            #""filter": "MacroPerformanceBenchmark""#,
            #""iterations": 2"#,
            #""mean_ms": \#(meanMS)"#,
            #""median_ms": \#(medianMS)"#,
            #""min_ms": \#(minMS)"#,
            #""max_ms": 10.0"#,
            #""stdev_ms": 0.0"#,
            #""samples_ms": [10.0, 10.0]"#,
        ])
        let json = "{\n  " + entries.joined(separator: ",\n  ") + "\n}\n"
        try json.write(to: baselineURL, atomically: true, encoding: .utf8)
    }

    func run(
        arguments: [String],
        additionalEnvironment: [String: String] = [:]
    ) throws -> MacroPerformanceScriptResult {
        let outputURL = rootURL.appendingPathComponent("output-\(UUID().uuidString).log")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            packageRootURL()
                .appendingPathComponent("Tools/measure-macro-performance.sh")
                .path,
        ] + arguments
        process.currentDirectoryURL = packageRootURL()
        process.standardOutput = outputHandle
        process.standardError = outputHandle

        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "GITHUB_ACTIONS")
        environment.removeValue(forKey: "ENFORCE_REGRESSION_GATE")
        environment["PATH"] = fakeBinURL.path + ":" + (environment["PATH"] ?? "")
        environment["FAKE_SWIFT_VERSION"] = swiftVersion
        environment["FAKE_SWIFT_MARKER"] = markerURL.path
        environment["FAKE_SWIFT_REPORT_JSON"] = reportJSON
        for (key, value) in additionalEnvironment {
            environment[key] = value
        }
        process.environment = environment

        try process.run()
        process.waitUntilExit()
        try outputHandle.synchronize()
        try outputHandle.close()

        let output = try String(contentsOf: outputURL, encoding: .utf8)
        return MacroPerformanceScriptResult(
            exitCode: process.terminationStatus,
            output: output
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
