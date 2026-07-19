//
//  StableHasher.swift
//  InnoDIWorkspaceAnalysis
//
//  The single deterministic hasher behind validation signatures, plugin
//  state-directory names, and external-path identities. It intentionally
//  avoids `Hashable`/`Hasher` because those are seeded per process; every
//  digest here must be stable across processes, runs, and toolchains.
//
//  Bytes are mixed in 8-byte little-endian blocks (MurmurHash3-style
//  per-lane mixing over two independent 64-bit lanes) instead of one
//  multiply per byte. A partial block is retained across `combine` calls,
//  so a byte sequence has one digest regardless of how callers chunk it.
//  Changing the mixing changes every digest, so bumps of
//  `ValidationDigestManifest`'s and the shared-run cache's versions must
//  accompany any edit here.
//
//  Keep exactly one implementation: earlier per-target copies drifted into
//  different low-state mixing, which is precisely the class of bug a
//  "stable" hasher cannot afford.
//

import Foundation

package struct StableHasher {
    private var highState: UInt64 = 14_695_981_039_346_656_037
    private var lowState: UInt64 = 0x9E37_79B9_7F4A_7C15
    private var combinedByteCount: UInt64 = 0
    private var pendingWord: UInt64 = 0
    private var pendingByteCount = 0

    package init() {}

    package mutating func combine(_ value: String) {
        var value = value
        value.withUTF8 { utf8 in
            combine(bytes: UnsafeRawBufferPointer(utf8))
        }
    }

    package mutating func combine(_ data: Data) {
        data.withUnsafeBytes { bytes in
            combine(bytes: bytes)
        }
    }

    /// Returns the 32-hex-character digest of everything combined so far.
    package func finalize() -> String {
        var high = highState
        var low = lowState
        if pendingByteCount > 0 {
            Self.mix(pendingWord, highState: &high, lowState: &low)
        }
        high ^= combinedByteCount
        low ^= combinedByteCount
        high = Self.finalMix(high &+ low)
        low = Self.finalMix(low ^ high)
        return paddedHex(high) + paddedHex(low)
    }

    private mutating func combine(bytes: UnsafeRawBufferPointer) {
        combinedByteCount &+= UInt64(bytes.count)

        var offset = 0
        while pendingByteCount > 0,
              pendingByteCount < 8,
              offset < bytes.count {
            pendingWord |= UInt64(bytes[offset]) << UInt64(pendingByteCount * 8)
            pendingByteCount += 1
            offset += 1
        }

        if pendingByteCount == 8 {
            Self.mix(
                pendingWord,
                highState: &highState,
                lowState: &lowState
            )
            pendingWord = 0
            pendingByteCount = 0
        }

        let blockEnd = bytes.count - (bytes.count - offset) % 8
        while offset < blockEnd {
            let word = UInt64(
                littleEndian: bytes.loadUnaligned(
                    fromByteOffset: offset,
                    as: UInt64.self
                )
            )
            Self.mix(word, highState: &highState, lowState: &lowState)
            offset += 8
        }

        while offset < bytes.count {
            pendingWord |= UInt64(bytes[offset]) << UInt64(pendingByteCount * 8)
            pendingByteCount += 1
            offset += 1
        }
    }

    private static func mix(
        _ word: UInt64,
        highState: inout UInt64,
        lowState: inout UInt64
    ) {
        var high = word &* 0x87C3_7B91_1142_53D5
        high = (high << 31) | (high >> 33)
        high &*= 0x4CF5_AD43_2745_937F
        highState ^= high
        highState = (highState << 27) | (highState >> 37)
        highState = highState &* 5 &+ 0x52DC_E729

        var low = word &* 0xFF51_AFD7_ED55_8CCD
        low ^= low >> 33
        low &*= 0xC4CE_B9FE_1A85_EC53
        lowState ^= low
        lowState = (lowState << 31) | (lowState >> 33)
        lowState = lowState &* 5 &+ 0x3856_5DD1
    }

    /// MurmurHash3's 64-bit finalizer.
    private static func finalMix(_ value: UInt64) -> UInt64 {
        var mixed = value
        mixed ^= mixed >> 33
        mixed &*= 0xFF51_AFD7_ED55_8CCD
        mixed ^= mixed >> 33
        mixed &*= 0xC4CE_B9FE_1A85_EC53
        mixed ^= mixed >> 33
        return mixed
    }

    private func paddedHex(_ value: UInt64) -> String {
        let raw = String(value, radix: 16)
        guard raw.count < 16 else {
            return raw
        }
        return String(repeating: "0", count: 16 - raw.count) + raw
    }
}
