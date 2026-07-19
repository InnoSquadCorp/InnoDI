//
//  StableHasher.swift
//  InnoDIWorkspaceAnalysis
//
//  The single deterministic hasher behind validation signatures, plugin
//  state-directory names, and external-path identities. It intentionally
//  avoids `Hashable`/`Hasher` because those are seeded per process; every
//  digest here must be stable across processes, runs, and toolchains.
//
//  Keep exactly one implementation: the earlier per-target copies drifted
//  into different low-state mixing, which is precisely the class of bug a
//  "stable" hasher cannot afford.
//

import Foundation

package struct StableHasher {
    private var highState: UInt64 = 14_695_981_039_346_656_037
    private var lowState: UInt64 = 1_099_511_628_211

    package init() {}

    package mutating func combine(_ value: String) {
        for byte in value.utf8 {
            combine(byte)
        }
    }

    package mutating func combine(_ data: Data) {
        for byte in data {
            combine(byte)
        }
    }

    /// Returns the 32-hex-character digest of everything combined so far.
    package func finalize() -> String {
        paddedHex(highState) + paddedHex(lowState)
    }

    private mutating func combine(_ byte: UInt8) {
        highState ^= UInt64(byte)
        highState &*= 1_099_511_628_211

        lowState &+= UInt64(byte) &* 0x9e37_79b9_7f4a_7c15
        lowState ^= lowState >> 33
        lowState &*= 0xff51_afd7_ed55_8ccd
        lowState ^= lowState >> 33
    }

    private func paddedHex(_ value: UInt64) -> String {
        let raw = String(value, radix: 16)
        guard raw.count < 16 else {
            return raw
        }
        return String(repeating: "0", count: 16 - raw.count) + raw
    }
}
