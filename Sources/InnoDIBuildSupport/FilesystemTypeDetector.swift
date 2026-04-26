//
//  FilesystemTypeDetector.swift
//  InnoDIBuildSupport
//
//  Classifies the filesystem under a given directory so the validation
//  coordinator can refuse to acquire its `O_CREAT | O_EXCL` lock on
//  filesystems where that operation is not atomic. See
//  `Sources/InnoDI/InnoDI.docc/lock-safety.md` for the full
//  documentation.
//
//  The detector is split into two layers:
//    1) `classify(fsName:)` (Darwin) / `classify(magic:)` (Linux)
//       are *pure* functions that map a filesystem identifier to a
//       `FilesystemSafetyClass`. Unit tests exercise these directly,
//       no syscalls required.
//    2) `FilesystemTypeDetector.classify(directory:)` performs the
//       `statfs(2)` syscall and forwards to the pure layer.
//
//  Adding support for a new filesystem only requires extending the
//  pure layer and writing a unit test.
//

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - C interop shim
//
// The C `statfs(2)` function and the C `struct statfs` are both
// imported into Swift under the name `statfs`. The Swift type checker
// resolves a bare `statfs(...)` call to the no-arg struct initializer
// instead of the function. We work around the collision by renaming
// the struct to `StatfsBuffer` for our local use and looking up the
// function pointer through `dlsym`. Both happen exactly once per
// classify call, so the cost is negligible.

private typealias StatfsBuffer = statfs
private typealias StatfsCFn = @convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<StatfsBuffer>?) -> Int32

private let sysStatfs: StatfsCFn = {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "statfs") else {
        // Fall back to a no-op that always reports failure; the
        // detector will then classify everything as `.unknown`,
        // which keeps the coordinator running rather than blocking.
        return { _, _ in -1 }
    }
    return unsafeBitCast(symbol, to: StatfsCFn.self)
}()

// MARK: - Public surface

/// Safety classification used by the validation coordinator to decide
/// whether `O_CREAT | O_EXCL` is reliable on a given directory.
package enum FilesystemSafetyClass: String, Sendable, Equatable {
    /// `O_CREAT | O_EXCL` is atomic on this filesystem.
    case safe
    /// `O_CREAT | O_EXCL` is *not* atomic on this filesystem; the
    /// coordinator must refuse to run unless the operator explicitly
    /// opts in via `INNODI_ALLOW_UNSAFE_LOCK=1`.
    case unsafe
    /// The filesystem identifier is not in the known list. Treated as
    /// "best-effort safe" — the coordinator emits a warning but still
    /// proceeds, so we never block a user just because their FS is
    /// new or rare.
    case unknown
}

/// Outcome of classifying a directory: the safety verdict plus the
/// raw filesystem identifier (so diagnostics can name it precisely).
package struct FilesystemClassification: Sendable, Equatable {
    package let safetyClass: FilesystemSafetyClass
    /// On Darwin: the value of `f_fstypename` (e.g. `"apfs"`, `"nfs"`).
    /// On Linux: the hex-formatted `f_type` magic number
    /// (e.g. `"0xef53"` for ext4).
    package let identifier: String
}

package enum FilesystemTypeDetector {
    /// Classifies the filesystem backing `directory`. Returns
    /// `.unknown` (with an empty identifier) if the syscall fails for
    /// any reason — callers must treat detection failure as
    /// non-blocking.
    package static func classify(directory: URL) -> FilesystemClassification {
        let path = directory.path(percentEncoded: false)
        return path.withCString { cPath -> FilesystemClassification in
            #if canImport(Darwin)
            var sb = StatfsBuffer()
            let rc = sysStatfs(cPath, &sb)
            if rc != 0 {
                return FilesystemClassification(safetyClass: .unknown, identifier: "")
            }
            let name = withUnsafePointer(to: &sb.f_fstypename) { ptr -> String in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { cstr in
                    String(cString: cstr)
                }
            }
            return FilesystemClassification(safetyClass: InnoDIBuildSupport.classify(fsName: name), identifier: name)
            #elseif canImport(Glibc)
            var sb = StatfsBuffer()
            let rc = sysStatfs(cPath, &sb)
            if rc != 0 {
                return FilesystemClassification(safetyClass: .unknown, identifier: "")
            }
            let magic = UInt64(bitPattern: Int64(sb.f_type))
            let identifier = String(format: "0x%llx", magic)
            return FilesystemClassification(safetyClass: InnoDIBuildSupport.classify(magic: magic), identifier: identifier)
            #else
            return FilesystemClassification(safetyClass: .unknown, identifier: "")
            #endif
        }
    }
}

// MARK: - Pure classification (Darwin)

/// Maps a Darwin `f_fstypename` value to its safety class. Pure — no
/// syscalls. Comparison is case-insensitive.
package func classify(fsName name: String) -> FilesystemSafetyClass {
    let lower = name.lowercased()
    switch lower {
    case "apfs", "hfs", "exfat", "msdos", "tmpfs", "devfs", "autofs":
        return .safe
    case "nfs", "webdav", "smbfs", "cifs":
        return .unsafe
    case "osxfuse", "macfuse", "fuse", "fusefs":
        // FUSE filesystems may or may not implement O_EXCL atomicity.
        // Be conservative — call them unsafe so the operator has to
        // opt in deliberately.
        return .unsafe
    default:
        return .unknown
    }
}

// MARK: - Pure classification (Linux)

/// Magic numbers from `<linux/magic.h>` we care about. Sourced from
/// the Linux kernel headers; numbers are stable ABI.
package enum LinuxFilesystemMagic {
    package static let nfs:        UInt64 = 0x6969
    package static let smb:        UInt64 = 0x517B
    package static let cifs:       UInt64 = 0xFF534D42
    package static let fuse:       UInt64 = 0x65735546
    package static let overlayfs:  UInt64 = 0x794C7630
    package static let aufs:       UInt64 = 0x61756673

    package static let ext4:       UInt64 = 0xEF53
    package static let btrfs:      UInt64 = 0x9123683E
    package static let xfs:        UInt64 = 0x58465342
    package static let tmpfs:      UInt64 = 0x01021994
    package static let f2fs:       UInt64 = 0xF2F52010
    package static let zfs:        UInt64 = 0x2FC12FC1
}

/// Maps a Linux `f_type` magic number to its safety class. Pure.
package func classify(magic: UInt64) -> FilesystemSafetyClass {
    switch magic {
    case LinuxFilesystemMagic.ext4,
         LinuxFilesystemMagic.btrfs,
         LinuxFilesystemMagic.xfs,
         LinuxFilesystemMagic.tmpfs,
         LinuxFilesystemMagic.f2fs,
         LinuxFilesystemMagic.zfs:
        return .safe
    case LinuxFilesystemMagic.nfs,
         LinuxFilesystemMagic.smb,
         LinuxFilesystemMagic.cifs,
         LinuxFilesystemMagic.fuse,
         LinuxFilesystemMagic.overlayfs,
         LinuxFilesystemMagic.aufs:
        return .unsafe
    default:
        return .unknown
    }
}
