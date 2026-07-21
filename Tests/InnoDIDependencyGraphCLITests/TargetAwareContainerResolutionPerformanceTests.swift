import Foundation
import InnoDICore
import InnoDIWorkspaceAnalysis
import Testing

@testable import InnoDIDependencyGraphCore

/// Opt-in benchmark for target-aware semantic-path suffix lookup.
///
/// ```sh
/// INNODI_SUFFIX_BENCH_ITERATIONS=1000 \
/// INNODI_SUFFIX_BENCH_PATHS=10000 \
///   swift test --filter TargetAwareContainerResolutionPerformanceTests
/// ```
///
/// Regular CI checks the semantic contract but deliberately avoids
/// machine-dependent timing assertions. Optimization work records at least
/// three independent process runs and compares their medians.
@Suite("Target-aware container resolution performance")
struct TargetAwareContainerResolutionPerformanceTests {
    @Test("Suffix indexing preserves both conservative matching directions")
    func suffixIndexPreservesResolutionContract() {
        let resolver = makeResolver(paths: [
            "AppContainer",
            "Feature.AppContainer",
            "Feature.Nested.AppContainer",
        ])

        let longerCandidate = resolver.resolve(
            reference("Nested.AppContainer")
        )
        let shorterCandidate = resolver.resolve(
            reference("Preview.Feature.AppContainer")
        )
        let singleComponentReverseMatch = resolver.resolve(
            reference("Preview.AppContainer")
        )

        #expect(longerCandidate.state == .resolved)
        #expect(longerCandidate.allCandidateIDs == [
            "benchmark::Feature.Nested.AppContainer"
        ])
        #expect(shorterCandidate.state == .resolved)
        #expect(shorterCandidate.allCandidateIDs == [
            "benchmark::Feature.AppContainer"
        ])
        #expect(singleComponentReverseMatch.state == .unresolved)
    }

    @Test(.disabled(if: ProcessInfo.processInfo.environment[
        "INNODI_SUFFIX_BENCH_ITERATIONS"
    ] == nil))
    func suffixLookupScalesAcrossLargeTargets() {
        let environment = ProcessInfo.processInfo.environment
        let iterations = max(
            1,
            Int(environment["INNODI_SUFFIX_BENCH_ITERATIONS"] ?? "1000")
                ?? 1_000
        )
        let pathCount = max(
            1,
            Int(environment["INNODI_SUFFIX_BENCH_PATHS"] ?? "10000")
                ?? 10_000
        )
        let resolver = makeResolver(paths: (0..<pathCount).map { index in
            "Feature.Namespace\(index).Container\(index)"
        })
        let references = (0..<iterations).map { index in
            let pathIndex = index % pathCount
            return reference(
                "Namespace\(pathIndex).Container\(pathIndex)"
            )
        }

        let warmup = resolver.resolve(references[0])
        #expect(warmup.state == .resolved)
        #expect(warmup.usedSuffixFallback)

        var resolvedCount = 0
        let duration = ContinuousClock().measure {
            for reference in references {
                if resolver.resolve(reference).state == .resolved {
                    resolvedCount += 1
                }
            }
        }

        #expect(resolvedCount == iterations)
        print(
            "Target-aware suffix benchmark: paths=\(pathCount), "
                + "iterations=\(iterations), "
                + "elapsed_ms=\(duration.suffixBenchmarkMilliseconds)"
        )
    }

    private func makeResolver(paths: [String]) -> GraphContainerResolver {
        let targetID = WorkspaceTargetID.swiftPM(
            packageIdentity: "suffix-benchmark",
            moduleName: "Benchmark"
        )
        let target = WorkspaceAnalysisTarget(
            id: targetID,
            packageIdentity: "suffix-benchmark",
            packageDisplayName: "Suffix Benchmark",
            packageDirectory: "/suffix-benchmark",
            targetName: "Benchmark",
            moduleName: "Benchmark",
            kind: .generic,
            role: .primary,
            sources: [],
            dependencies: []
        )
        let manifest = WorkspaceAnalysisManifest(
            rootPackageIdentity: "suffix-benchmark",
            rootPackageDirectory: "/suffix-benchmark",
            primaryTargetID: targetID,
            targets: [target]
        )
        let nodes = paths.map { path in
            DependencyGraphNode(
                id: "benchmark::\(path)",
                displayName: path,
                semanticPath: path,
                isRoot: false,
                requiredInputs: []
            )
        }
        return TargetAwareContainerResolutionIndex(
            manifest: manifest,
            nodesByTargetID: [targetID: nodes],
            aliasesByTargetID: [:],
            exportedImportsByTargetID: [:],
            validateDAG: true
        ).resolver(from: targetID, sourceImports: .empty)
    }

    private func reference(_ path: String) -> SemanticTypeReference {
        SemanticTypeReference(
            displayPath: path,
            components: path.split(separator: ".").map(String.init)
        )
    }
}

private extension Duration {
    var suffixBenchmarkMilliseconds: Double {
        let components = self.components
        let seconds = Double(components.seconds) * 1_000
        let attoseconds = Double(components.attoseconds) / 1e15
        return seconds + attoseconds
    }
}
