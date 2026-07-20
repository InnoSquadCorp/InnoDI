import Foundation
import InnoDIWorkspaceAnalysis
import SwiftParser
import Testing

@testable import InnoDIBuildSupport

/// Opt-in benchmark for the full-source qualifier preflight.
///
/// ```sh
/// INNODI_QUALIFIER_BENCH_ITERATIONS=5 \
/// INNODI_QUALIFIER_BENCH_SITES=400 \
/// INNODI_QUALIFIER_BENCH_SHADOWS=2000 \
///   swift test --filter GeneratedQualifierBuildValidatorPerformanceTests
/// ```
///
/// The synthetic workspace deliberately contains many unrelated declarations.
/// This catches regressions that make every macro site rescan every shadow,
/// while keeping regular CI free from machine-dependent timing assertions.
@Suite("Generated qualifier validator performance")
struct GeneratedQualifierBuildValidatorPerformanceTests {
    @Test(.disabled(if: ProcessInfo.processInfo.environment[
        "INNODI_QUALIFIER_BENCH_ITERATIONS"
    ] == nil))
    func unrelatedShadowsDoNotScaleWithEveryMacroSite() {
        let environment = ProcessInfo.processInfo.environment
        let iterations = max(
            1,
            Int(environment[
                "INNODI_QUALIFIER_BENCH_ITERATIONS"
            ] ?? "5") ?? 5
        )
        let siteCount = max(
            1,
            Int(environment["INNODI_QUALIFIER_BENCH_SITES"] ?? "400")
                ?? 400
        )
        let shadowCount = max(
            1,
            Int(environment["INNODI_QUALIFIER_BENCH_SHADOWS"] ?? "2000")
                ?? 2_000
        )
        let snapshot = makePerformanceSnapshot(
            siteCount: siteCount,
            shadowCount: shadowCount
        )

        let warmup = GeneratedQualifierBuildValidator.validate(
            snapshot: snapshot
        )
        #expect(warmup.issues.count == 1)
        #expect(warmup.issues.first?.notes.count == siteCount)

        let clock = ContinuousClock()
        var finalReport = ValidationIssueReport(issues: [])
        let duration = clock.measure {
            for _ in 0..<iterations {
                finalReport = GeneratedQualifierBuildValidator.validate(
                    snapshot: snapshot
                )
            }
        }

        #expect(finalReport.issues.count == 1)
        #expect(finalReport.issues.first?.notes.count == siteCount)
        print(
            "Generated qualifier benchmark: sites=\(siteCount), "
                + "shadows=\(shadowCount), iterations=\(iterations), "
                + "elapsed_ms=\(duration.qualifierBenchmarkMilliseconds)"
        )
    }

    private func makePerformanceSnapshot(
        siteCount: Int,
        shadowCount: Int
    ) -> WorkspaceSourceSnapshot {
        let containers = (0..<siteCount).map { index in
            """
            @DIContainer(mainActor: true)
            struct Container\(index) {
                @Provide(.input) var value: Int
            }
            """
        }.joined(separator: "\n")
        let shadows = ["struct Swift {}"] + (0..<shadowCount).map { index in
            "struct UnrelatedQualifier\(index) {}"
        }
        let rootURL = URL(fileURLWithPath: "/qualifier-benchmark")
        let fixtures = [
            ("Containers.swift", containers),
            ("Shadows.swift", shadows.joined(separator: "\n")),
        ]
        return WorkspaceSourceSnapshot(
            rootPath: rootURL.path,
            rootURL: rootURL,
            files: fixtures.map { path, source in
                WorkspaceSourceFile(
                    relativePath: path,
                    fileURL: rootURL.appendingPathComponent(path),
                    syntax: Parser.parse(source: source)
                )
            }
        )
    }
}

private extension Duration {
    var qualifierBenchmarkMilliseconds: Double {
        let components = self.components
        let seconds = Double(components.seconds) * 1_000
        let attoseconds = Double(components.attoseconds) / 1e15
        return seconds + attoseconds
    }
}
