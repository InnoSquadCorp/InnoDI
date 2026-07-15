import Foundation
import InnoDITestSupport
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
@_spi(Testing) import SwiftSyntaxMacrosGenericTestSupport
import Testing

@testable import InnoDIMacros

/// In-process macro expansion benchmark.
///
/// The shell harness `Tools/measure-macro-performance.sh` defaults to one
/// `swift test` invocation, one test case, and N macro expansions timed with
/// `ContinuousClock`. This avoids paying cold build-graph and test-runtime
/// startup costs for every sample. The harness's explicit `--subprocess`
/// mode retains the slower process-level measurement when that signal is
/// needed.
///
/// Outputs are written to `INNODI_MACRO_BENCH_OUTPUT` when set (the shell
/// harness picks that path up), otherwise logged to stdout. The env var is
/// the only way to trigger the benchmark: filtering on the test alone won't
/// write any file, keeping regular `swift test` runs free of throw-away
/// artifacts.
@Suite("Macro performance benchmark", .tags(.macroBenchmark))
struct MacroPerformanceBenchmark {
    private static let macros: [String: any Macro.Type] = [
        "DIContainer": DIContainerMacro.self,
        "Provide": ProvideMacro.self,
        "_InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
        "InnoDI._InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
        "SubContainer": SubContainerMacro.self,
        "_InnoDISubContainerAccessor": InnoDISubContainerAccessorMacro.self,
        "InnoDI._InnoDISubContainerAccessor": InnoDISubContainerAccessorMacro.self,
        "DIEnvironmentBridge": DIEnvironmentBridgeMacro.self,
    ]

    /// A composite fixture that exercises the macro surface a real consumer
    /// hits in one expansion: a root `@DIContainer` with mixed scopes,
    /// a feature-root-generating `@SubContainer`, and a SwiftUI
    /// `@DIEnvironmentBridge`. Adding a new macro to the dictionary above without
    /// also extending this fixture leaves the new path unmeasured.
    private static let representativeSource = """
    @DIEnvironmentBridge([
        (member: "userService", environment: \\EnvironmentValues.userService),
    ])
    @DIContainer
    struct AppContainer {
        @Provide(.input) var config: AppConfig
        @Provide(.shared, factory: { (config: AppConfig) in APIClient(config: config) })
        var apiClient: APIClient
        @Provide(.shared, factory: { (apiClient: APIClient) in UserService(api: apiClient) })
        var userService: UserService
        @Provide(.shared, factory: { (apiClient: APIClient, userService: UserService) in
            FeatureService(api: apiClient, users: userService)
        })
        var featureService: FeatureService
        @Provide(.transient, factory: { (apiClient: APIClient) in RequestBuilder(api: apiClient) })
        var requestBuilder: RequestBuilder
        @SubContainer(scope: .shared, featureRoot: DashboardRootView.self)
        var dashboard: DashboardContainer
    }
    """

    @Test(.disabled(if: ProcessInfo.processInfo.environment["INNODI_MACRO_BENCH_ITERATIONS"] == nil))
    func measureExpansion() throws {
        let rawIterations = Int(ProcessInfo.processInfo.environment["INNODI_MACRO_BENCH_ITERATIONS"] ?? "50") ?? 50
        let iterations = max(1, rawIterations)
        let warmupIterations = max(1, iterations / 10)

        // Warmup to stabilize cache / JIT paths.
        for _ in 0..<warmupIterations {
            runOne()
        }

        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        let clock = ContinuousClock()

        for _ in 0..<iterations {
            let duration = clock.measure {
                runOne()
            }
            samples.append(duration.milliseconds)
        }

        let mean = samples.reduce(0, +) / Double(samples.count)
        let min = samples.min() ?? 0
        let max = samples.max() ?? 0
        let stdev: Double = {
            guard samples.count > 1 else { return 0 }
            let variance = samples.reduce(0) { acc, value in acc + pow(value - mean, 2) } / Double(samples.count - 1)
            return variance.squareRoot()
        }()

        let swiftVersion = ProcessInfo.processInfo.environment["SWIFT_VERSION"] ?? "(unset)"
        let isoTimestamp = ISO8601DateFormatter().string(from: Date())
        let samplesString = samples.map { String(format: "%.3f", $0) }.joined(separator: ", ")
        let report = """
        {
          "updated_at": "\(isoTimestamp)",
          "swift_version": "\(swiftVersion)",
          "source": "in-process-macro-benchmark",
          "iterations": \(iterations),
          "warmup_iterations": \(warmupIterations),
          "mean_ms": \(String(format: "%.3f", mean)),
          "min_ms": \(String(format: "%.3f", min)),
          "max_ms": \(String(format: "%.3f", max)),
          "stdev_ms": \(String(format: "%.3f", stdev)),
          "samples_ms": [\(samplesString)]
        }

        """

        if let outputPath = ProcessInfo.processInfo.environment["INNODI_MACRO_BENCH_OUTPUT"] {
            try report.write(toFile: outputPath, atomically: true, encoding: .utf8)
        } else {
            print(report)
        }
    }

    private func runOne() {
        let specs = Self.macros.mapValues { MacroSpec(type: $0) }
        var observedFailures = 0
        SwiftSyntaxMacrosGenericTestSupport.assertMacroExpansion(
            Self.representativeSource,
            expandedSource: Self.representativeSource,
            diagnostics: [],
            macroSpecs: specs,
            testModuleName: "BenchModule",
            testFileName: "bench.swift",
            indentationWidth: .spaces(4),
            failureHandler: { _ in
                observedFailures += 1
            },
            fileID: #fileID,
            filePath: #filePath,
            line: #line,
            column: #column
        )
        // The expansion intentionally disagrees with the fed expected source,
        // so a failure is expected — we only care about the cost of running
        // the expansion machinery, not the comparison result. Touching the
        // counter keeps the optimizer from eliding the call.
        _ = observedFailures
    }
}

private extension Tag {
    @Tag static var macroBenchmark: Self
}

private extension Duration {
    var milliseconds: Double {
        let attos = components.attoseconds
        let secs = Double(components.seconds) * 1_000.0
        let subSec = Double(attos) / 1_000_000_000_000_000.0  // atto -> ms: /1e15
        return secs + subSec
    }
}
