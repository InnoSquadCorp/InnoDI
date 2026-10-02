// Focused compiler-analysis microbenchmark; not a consumer/runtime benchmark.
// Compile together with Sources/InnoDICore/DependencyAvailabilityIndex.swift.
import Foundation

typealias Member = DependencyAvailabilityIndex.Member

private struct Query {
    let name: String
    let consumer: Int
}

/// Baseline algorithm from DependencyResolution.swift at 6725e08. Keep the
/// per-reference set materialization; this is the measured behavior, not an
/// artificially slowed implementation. The descriptor conversion is outside
/// both measurements because both receive the same syntax-free input here.
private struct ReferenceResolver {
    let members: [Member]
    let knownNames: Set<String>

    init(_ members: [Member]) {
        self.members = members
        self.knownNames = Set(members.map(\.name))
    }

    func availableNames(at index: Int) -> Set<String> {
        guard members.indices.contains(index) else { return [] }
        switch members[index].kind {
        case .input: return []
        case .transient: return knownNames
        case .synchronousShared, .asynchronousShared:
            let inputs = Set(members.lazy.filter { $0.kind == .input }.map(\.name))
            let priorSync = Set(members[..<index].lazy.filter {
                $0.kind == .synchronousShared
            }.map(\.name))
            if members[index].kind == .asynchronousShared {
                let allSync = Set(members.lazy.filter {
                    $0.kind == .synchronousShared
                }.map(\.name))
                let priorAsync = Set(members[..<index].lazy.filter {
                    $0.kind == .asynchronousShared
                }.map(\.name))
                return inputs.union(allSync).union(priorAsync)
            }
            return inputs.union(priorSync)
        }
    }

    func status(_ query: Query) -> DependencyAvailabilityIndex.Status {
        guard knownNames.contains(query.name) else { return .unknown }
        return availableNames(at: query.consumer).contains(query.name) ? .available : .unavailable
    }
}

@inline(never)
private func legacy(_ members: [Member], _ queries: [Query]) -> Int {
    let resolver = ReferenceResolver(members)
    var checksum = 0
    for query in queries {
        checksum += resolver.status(query) == .available ? 1 : 0
    }
    return checksum
}

@inline(never)
private func indexed(_ members: [Member], _ queries: [Query]) -> Int {
    let resolver = DependencyAvailabilityIndex(members: members)
    var checksum = 0
    for query in queries {
        checksum += resolver.status(of: query.name, forMemberAt: query.consumer) == .available ? 1 : 0
    }
    return checksum
}

@main
struct DependencyAvailabilityBenchmark {
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        let samples = max(1, Int(environment["INNODI_INDEX_SAMPLES"] ?? "30") ?? 30)
        let warmups = max(0, Int(environment["INNODI_INDEX_WARMUPS"] ?? "3") ?? 3)
        let sizes = (environment["INNODI_INDEX_SIZES"] ?? "20,50,200,1000")
            .split(separator: ",").compactMap { Int($0) }.filter { $0 > 0 }
        var results: [[String: Any]] = []
        let clock = ContinuousClock()
        var checksum = 0
        for count in sizes {
            let members: [Member] = (0..<count).map { index in
                let kind: DependencyAvailabilityIndex.Kind = index % 13 == 0 ? .input
                    : index >= count * 9 / 10 ? .transient
                    : index % 3 == 0 ? .asynchronousShared : .synchronousShared
                return .init(name: "provider\(index)", kind: kind)
            }
            let reference = ReferenceResolver(members)
            for density in ["sparse", "dense"] {
                var queries: [Query] = []
                for consumer in members.indices {
                    // Only prior non-transient providers: a deterministic DAG,
                    // no service work or construction-side effects to skew costs.
                    let available = reference.availableNames(at: consumer)
                    let names = members[..<consumer].filter {
                        $0.kind != .transient && available.contains($0.name)
                    }.map(\.name)
                    for name in density == "sparse" ? Array(names.suffix(3)) : names {
                        queries.append(.init(name: name, consumer: consumer))
                    }
                }
                FileHandle.standardError.write(Data("Measuring N=\(count) \(density), E=\(queries.count)\n".utf8))
                precondition(legacy(members, queries) == indexed(members, queries))
                for _ in 0..<warmups {
                    checksum += legacy(members, queries)
                    checksum += indexed(members, queries)
                }
                var before: [Double] = []
                var after: [Double] = []
                for sample in 0..<samples {
                    // Alternate within the same process, machine and workload.
                    let order = sample.isMultiple(of: 2) ? [false, true] : [true, false]
                    for candidate in order {
                        let duration = clock.measure {
                            checksum += candidate ? indexed(members, queries) : legacy(members, queries)
                        }
                        let elapsed = Double(duration.components.seconds) * 1_000
                            + Double(duration.components.attoseconds) / 1e15
                        if candidate { after.append(elapsed) } else { before.append(elapsed) }
                    }
                }
                results.append([
                    "members": count, "edges": queries.count, "density": density,
                    "baseline_ms": before, "indexed_ms": after,
                ])
            }
        }
        let report: [String: Any] = [
            "schema_version": 1,
            "scope": "syntax-free availability index construction plus edge lookup",
            "baseline_sha": "6725e08b6da5d2ceeda61ed795adca5fadda564c",
            "compiler": environment["SWIFT_VERSION"] ?? "record separately",
            "candidate_source_sha256": environment["INNODI_INDEX_SOURCE_SHA256"] ?? "record separately",
            "cpu": environment["INNODI_INDEX_CPU"] ?? "record separately",
            "compile_flags": "-O -swift-version 6 -strict-concurrency=complete -warnings-as-errors",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "samples": samples, "warmups": warmups, "checksum": checksum,
            "results": results,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
