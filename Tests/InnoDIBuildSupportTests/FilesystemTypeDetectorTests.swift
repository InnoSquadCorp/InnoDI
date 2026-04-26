import Foundation
import Testing

@testable import InnoDIBuildSupport

@Suite("FilesystemTypeDetector classification (pure layer)")
struct FilesystemTypeDetectorTests {

    // MARK: - Darwin classification

    @Test("APFS classifies as safe")
    func apfsIsSafe() {
        #expect(classify(fsName: "apfs") == .safe)
        #expect(classify(fsName: "APFS") == .safe) // case-insensitive
    }

    @Test("HFS+ classifies as safe")
    func hfsIsSafe() {
        #expect(classify(fsName: "hfs") == .safe)
    }

    @Test("Other local filesystems classify as safe")
    func otherLocalsAreSafe() {
        #expect(classify(fsName: "exfat") == .safe)
        #expect(classify(fsName: "msdos") == .safe)
        #expect(classify(fsName: "tmpfs") == .safe)
        #expect(classify(fsName: "devfs") == .safe)
        #expect(classify(fsName: "autofs") == .safe)
    }

    @Test("Network filesystems classify as unsafe")
    func networkFilesystemsAreUnsafe() {
        #expect(classify(fsName: "nfs") == .unsafe)
        #expect(classify(fsName: "smbfs") == .unsafe)
        #expect(classify(fsName: "cifs") == .unsafe)
        #expect(classify(fsName: "webdav") == .unsafe)
    }

    @Test("FUSE-style filesystems classify as unsafe (conservative)")
    func fuseFilesystemsAreUnsafe() {
        #expect(classify(fsName: "osxfuse") == .unsafe)
        #expect(classify(fsName: "macfuse") == .unsafe)
        #expect(classify(fsName: "fuse") == .unsafe)
        #expect(classify(fsName: "fusefs") == .unsafe)
    }

    @Test("Unrecognized filesystem identifiers classify as unknown")
    func unrecognizedAreUnknown() {
        #expect(classify(fsName: "zfs") == .unknown)        // Mac ZFS — exotic
        #expect(classify(fsName: "ntfs") == .unknown)
        #expect(classify(fsName: "weirdfs") == .unknown)
        #expect(classify(fsName: "") == .unknown)
    }

    // MARK: - Linux classification (pure)

    @Test("Linux ext4 / btrfs / xfs / tmpfs / f2fs / zfs classify as safe")
    func linuxLocalsAreSafe() {
        #expect(classify(magic: LinuxFilesystemMagic.ext4) == .safe)
        #expect(classify(magic: LinuxFilesystemMagic.btrfs) == .safe)
        #expect(classify(magic: LinuxFilesystemMagic.xfs) == .safe)
        #expect(classify(magic: LinuxFilesystemMagic.tmpfs) == .safe)
        #expect(classify(magic: LinuxFilesystemMagic.f2fs) == .safe)
        #expect(classify(magic: LinuxFilesystemMagic.zfs) == .safe)
    }

    @Test("Linux NFS / SMB / CIFS / FUSE / overlayfs / aufs classify as unsafe")
    func linuxNetworkAndOverlayAreUnsafe() {
        #expect(classify(magic: LinuxFilesystemMagic.nfs) == .unsafe)
        #expect(classify(magic: LinuxFilesystemMagic.smb) == .unsafe)
        #expect(classify(magic: LinuxFilesystemMagic.cifs) == .unsafe)
        #expect(classify(magic: LinuxFilesystemMagic.fuse) == .unsafe)
        #expect(classify(magic: LinuxFilesystemMagic.overlayfs) == .unsafe)
        #expect(classify(magic: LinuxFilesystemMagic.aufs) == .unsafe)
    }

    @Test("Unrecognized Linux magic numbers classify as unknown")
    func unrecognizedLinuxMagicAreUnknown() {
        #expect(classify(magic: 0x1234567) == .unknown)
        #expect(classify(magic: 0) == .unknown)
    }

    // MARK: - Live syscall

    @Test("Classifying the temporary directory returns a non-empty identifier")
    func liveClassificationOfTempDirectory() {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let result = FilesystemTypeDetector.classify(directory: temp)
        // Whatever the classification, the identifier must be populated;
        // returning an empty string would mean the syscall failed and
        // the caller can no longer surface a useful diagnostic.
        #expect(!result.identifier.isEmpty,
                "classify should yield a non-empty filesystem identifier for an existing directory; got \(result)")
        // /tmp on Apple CI (APFS) and Linux CI (ext4 / tmpfs) is safe.
        // Allow `.safe` or `.unknown` (CI may use exotic FUSE) but not
        // `.unsafe` — there is no realistic CI environment where /tmp
        // is on NFS or SMB.
        #expect(result.safetyClass != .unsafe,
                "Expected /tmp to be safe or unknown; got \(result)")
    }
}

@Suite("ValidationCoordinatorLockPolicy.allowUnsafeFilesystem environment override")
struct LockPolicyAllowUnsafeFilesystemTests {

    @Test("Default is false")
    func defaultIsFalse() {
        #expect(ValidationCoordinatorLockPolicy.default.allowUnsafeFilesystem == false)
    }

    @Test("Recognized truthy values enable the bypass")
    func truthyValuesEnableBypass() {
        for raw in ["1", "true", "TRUE", "yes", "Y", "on"] {
            let policy = ValidationCoordinatorLockPolicy(
                environment: [ValidationCoordinatorLockPolicy.EnvKey.allowUnsafeLock: raw],
                warningHandler: { _ in }
            )
            #expect(policy.allowUnsafeFilesystem,
                    "Expected '\(raw)' to enable the bypass")
        }
    }

    @Test("Recognized falsy or unset values keep the bypass disabled")
    func falsyValuesKeepBypassDisabled() {
        for raw in ["0", "false", "no", "off", ""] {
            let policy = ValidationCoordinatorLockPolicy(
                environment: [ValidationCoordinatorLockPolicy.EnvKey.allowUnsafeLock: raw],
                warningHandler: { _ in }
            )
            #expect(!policy.allowUnsafeFilesystem,
                    "Expected '\(raw)' to keep bypass disabled")
        }
        let unset = ValidationCoordinatorLockPolicy(
            environment: [:],
            warningHandler: { _ in }
        )
        #expect(!unset.allowUnsafeFilesystem)
    }

    @Test("Unrecognized values fall back to disabled (fail-safe)")
    func unrecognizedValuesFallSafe() {
        let policy = ValidationCoordinatorLockPolicy(
            environment: [ValidationCoordinatorLockPolicy.EnvKey.allowUnsafeLock: "maybe"],
            warningHandler: { _ in }
        )
        #expect(!policy.allowUnsafeFilesystem)
    }
}
