import Foundation
import InnoDIWorkspaceAnalysis
import Testing

@Suite("StableHasher")
struct StableHasherTests {
    @Test("Golden digests cover empty, block-boundary, binary, and Unicode input")
    func goldenDigests() {
        let vectors: [(Data, String)] = [
            (Data(), "8effae66271ed426299ec6326efcb1fb"),
            (Data("a".utf8), "5e0d78d334b7c962064397b1b2abd0bd"),
            (Data("1234567".utf8), "18a318e08ba41053eeaacc306e6ecbcb"),
            (Data("12345678".utf8), "5abfd43fa296e223f608b5fa8c36aeb9"),
            (Data("123456789".utf8), "021800dc3fcacc8fa5fa251fc0576d03"),
            (
                Data([0, 1, 0, 2, 0, 3, 0, 4, 0]),
                "979caaf6270da27b6e1e28a0f4928584"
            ),
            (
                Data("안녕 InnoDI".utf8),
                "763b4218b241da8d6728db71075924ae"
            ),
        ]

        for (input, expected) in vectors {
            #expect(digest(input) == expected)
        }
    }

    @Test("String and Data entry points hash the same UTF-8 bytes")
    func stringAndDataParity() {
        let value = "macro-first DI 🧩"
        var stringHasher = StableHasher()
        stringHasher.combine(value)

        #expect(stringHasher.finalize() == digest(Data(value.utf8)))
    }

    @Test("Digest is independent of combine call boundaries")
    func chunkBoundaryIndependence() {
        let input = Data((0...64).map(UInt8.init))
        let expected = digest(input)

        for split in 0...input.count {
            var hasher = StableHasher()
            hasher.combine(Data(input.prefix(split)))
            hasher.combine(Data())
            hasher.combine(Data(input.suffix(input.count - split)))
            #expect(hasher.finalize() == expected)
        }

        var byteAtATime = StableHasher()
        for byte in input {
            byteAtATime.combine(Data([byte]))
        }
        #expect(byteAtATime.finalize() == expected)
    }

    @Test("Finalizing does not consume a pending partial block")
    func finalizeDoesNotConsumePendingBytes() {
        var hasher = StableHasher()
        hasher.combine("1234")
        let partialDigest = hasher.finalize()
        hasher.combine("5678")

        #expect(partialDigest == digest(Data("1234".utf8)))
        #expect(hasher.finalize() == digest(Data("12345678".utf8)))
    }

    private func digest(_ data: Data) -> String {
        var hasher = StableHasher()
        hasher.combine(data)
        return hasher.finalize()
    }
}

/// Opt-in comparison with the byte-at-a-time implementation replaced in 5.0.
/// Run with:
///
/// ```sh
/// INNODI_STABLE_HASHER_BENCH_ITERATIONS=20 \
///   swift test --filter StableHasherPerformanceBenchmark
/// ```
///
/// Regular test runs skip the measurement so machine load cannot make CI
/// correctness flaky. The benchmark still asserts its basic premise when a
/// maintainer explicitly runs it and prints reproducible timing inputs.
@Suite("StableHasher performance benchmark")
struct StableHasherPerformanceBenchmark {
    @Test(.disabled(if: ProcessInfo.processInfo.environment[
        "INNODI_STABLE_HASHER_BENCH_ITERATIONS"
    ] == nil))
    func compareBlockAndLegacyByteMixing() {
        let environment = ProcessInfo.processInfo.environment
        let iterations = max(
            1,
            Int(environment["INNODI_STABLE_HASHER_BENCH_ITERATIONS"] ?? "20") ?? 20
        )
        let rawInputSize = Int(
            environment["INNODI_STABLE_HASHER_BENCH_BYTES"] ?? "1048576"
        ) ?? 1_048_576
        let inputSize = max(1, rawInputSize)
        let input = Data((0..<inputSize).map { UInt8(truncatingIfNeeded: $0) })

        // Warm both implementations before timing to keep one-time runtime
        // initialization out of the comparison.
        _ = blockDigest(input)
        _ = legacyByteDigest(input)

        let clock = ContinuousClock()
        var observedBlockDigest = ""
        let blockDuration = clock.measure {
            for _ in 0..<iterations {
                observedBlockDigest = blockDigest(input)
            }
        }
        var observedLegacyDigest = ""
        let legacyDuration = clock.measure {
            for _ in 0..<iterations {
                observedLegacyDigest = legacyByteDigest(input)
            }
        }

        #expect(observedBlockDigest.count == 32)
        #expect(observedLegacyDigest.count == 32)
        #expect(blockDuration < legacyDuration)

        let blockMilliseconds = blockDuration.milliseconds
        let legacyMilliseconds = legacyDuration.milliseconds
        let speedup = legacyMilliseconds / blockMilliseconds
        print(
            "StableHasher benchmark: bytes=\(inputSize), " +
            "iterations=\(iterations), block_ms=\(blockMilliseconds), " +
            "legacy_ms=\(legacyMilliseconds), speedup=\(speedup)x"
        )
    }

    private func blockDigest(_ data: Data) -> String {
        var hasher = StableHasher()
        hasher.combine(data)
        return hasher.finalize()
    }

    /// The pre-5.0 implementation retained only as a benchmark baseline.
    private func legacyByteDigest(_ data: Data) -> String {
        var highState: UInt64 = 14_695_981_039_346_656_037
        var lowState: UInt64 = 1_099_511_628_211

        for byte in data {
            highState ^= UInt64(byte)
            highState &*= 1_099_511_628_211

            lowState &+= UInt64(byte) &* 0x9E37_79B9_7F4A_7C15
            lowState ^= lowState >> 33
            lowState &*= 0xFF51_AFD7_ED55_8CCD
            lowState ^= lowState >> 33
        }

        return paddedHex(highState) + paddedHex(lowState)
    }

    private func paddedHex(_ value: UInt64) -> String {
        let raw = String(value, radix: 16)
        return String(repeating: "0", count: max(0, 16 - raw.count)) + raw
    }
}

private extension Duration {
    var milliseconds: Double {
        let components = self.components
        return Double(components.seconds) * 1_000.0 +
            Double(components.attoseconds) / 1_000_000_000_000_000.0
    }
}
