import Foundation

struct SampleStats: Codable {
    let iterations: Int
    let mean: Double
    let stdev: Double
    let p50: Double
    let p95: Double
    let samples: [Double]
}

func stats(from samples: [Double]) -> SampleStats {
    let sorted = samples.sorted()
    let count = sorted.count
    let mean = sorted.reduce(0, +) / Double(max(1, count))
    let variance = count > 1
        ? sorted.reduce(0) { $0 + pow($1 - mean, 2) } / Double(count - 1)
        : 0
    let p50 = percentile(sorted, 0.50)
    let p95 = percentile(sorted, 0.95)
    return SampleStats(
        iterations: count,
        mean: mean,
        stdev: sqrt(variance),
        p50: p50,
        p95: p95,
        samples: samples
    )
}

func percentile(_ sorted: [Double], _ q: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let clamped = min(max(q, 0), 1)
    let raw = clamped * Double(sorted.count - 1)
    let lower = Int(floor(raw))
    let upper = Int(ceil(raw))
    if lower == upper { return sorted[lower] }
    let weight = raw - Double(lower)
    return sorted[lower] * (1.0 - weight) + sorted[upper] * weight
}

let sampleArg = CommandLine.arguments.dropFirst().first
let samples = sampleArg?
    .split(separator: ",")
    .compactMap { Double($0) } ?? []

let result = stats(from: samples)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

if let data = try? encoder.encode(result),
   let output = String(data: data, encoding: .utf8) {
    print(output)
} else {
    fputs("failed to encode benchmark stats\n", stderr)
    exit(1)
}
