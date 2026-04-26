# Lock Safety

How InnoDI's build-time validation coordinator serializes runs across
concurrent builds, and what to do when it fails.

## Overview

When `swift build` and Xcode invoke the InnoDI build plugin in parallel —
for example a CLI build alongside an open Xcode window — the plugin
serializes the live DAG-validation step through a single POSIX lock per
*signature* (the normalized hash of every container source). The lock is
acquired with `open(O_CREAT | O_EXCL | O_RDWR)` against a file inside
SPM's scratch directory.

This article explains the requirements that lock places on the
filesystem, what the error messages mean, and how to recover when a
build fails to acquire the lock.

## Filesystem requirements

`O_CREAT | O_EXCL` is **atomic** on the local filesystems Apple and
Linux ship by default:

| Filesystem | Status | Notes |
|---|---|---|
| APFS | ✅ supported | Default macOS / iOS simulator builds. |
| HFS+ | ✅ supported | |
| ext4 / btrfs / xfs | ✅ supported | Linux SPM builds. |
| tmpfs | ✅ supported | Often the SPM scratch path on CI. |
| **NFS** | ❌ unsupported by default | InnoDI classifies NFS mounts as unsafe because the detector cannot reliably distinguish mount versions and lock semantics. Redirect the scratch path to a local volume or opt in with `INNODI_ALLOW_UNSAFE_LOCK=1`. |
| **SMB / CIFS** | ❌ unsupported | Atomicity is not guaranteed. |
| **WebDAV** | ❌ unsupported | Darwin `webdav` volumes are network-backed and classified as unsafe by default. |
| **FUSE / macFUSE / osxfuse** | ❌ unsupported by default | FUSE filesystems vary by driver; InnoDI classifies them as unsafe so operators must opt in deliberately. |
| Linux overlayfs / AUFS | ❌ unsupported by default | The detector classifies these as unsafe. Prefer a local bind-mounted scratch path. |

If the build plugin must run where the derived-data directory is backed
by a network share, redirect SPM's scratch path:

```sh
swift build --scratch-path /tmp/innodi-cache
```

InnoDI auto-detects the filesystem under the lock directory at the
start of every run. If it lands on an unsafe one, the coordinator
fails fast with the diagnostic block shown in
[Refusing on unsafe filesystems](#refusing-on-unsafe-filesystems).
Set `INNODI_ALLOW_UNSAFE_LOCK=1` to bypass the check (you keep the
risk).

## Refusing on unsafe filesystems

When the auto-detector classifies the lock directory as `nfs`,
`smbfs`, `cifs`, `webdav`, or a FUSE-backed filesystem, the coordinator
emits this stderr block and exits with status `1`:

```text
InnoDI refuses to acquire its validation coordinator lock on this filesystem.
  path:        /Volumes/CIShare/.../validation-lock
  filesystem:  nfs (classified as unsafe)

Reason:
  `O_CREAT | O_EXCL` is not reliable on NFS, SMB/CIFS, and some FUSE-backed
  filesystems. Two concurrent builds can both believe they own the lock,
  which would corrupt the shared-run validation cache.

Suggested actions:
  1) Move SPM's scratch path to a local filesystem:
       swift build --scratch-path /tmp/innodi-cache
  2) If you understand the risk and want to proceed anyway:
       INNODI_ALLOW_UNSAFE_LOCK=1 swift build
```

If the detector returns `unknown` (a filesystem InnoDI does not yet
recognize) the coordinator emits a single-line warning and proceeds —
we never block on an unrecognized filesystem because the most common
cause is a new, perfectly safe filesystem we haven't added to the
table yet. Filesystems we have not classified yet are tracked in
`Sources/InnoDIBuildSupport/FilesystemTypeDetector.swift` — please
open an issue if your filesystem warrants explicit handling.

## Reading a lock-timeout diagnostic

When the coordinator gives up waiting for the lock (default `30s`,
override via `INNODI_LOCK_TIMEOUT`), the plugin emits a structured
stderr block:

```text
Timed out waiting for the InnoDI validation coordinator lock.
  path:        /…/derived-data/…/validation-lock
  waited:      30.00s
  holder pid:  74211
  holder age:  42.18s
  boot id:     B6D5…
Suggested actions:
  1) Re-run the build. Concurrent SPM/Xcode invocations are the most common cause.
  2) Increase the wait window: INNODI_LOCK_TIMEOUT=<seconds> swift build  (default 30).
  3) Lower the stale threshold if the holder pid is dead: INNODI_STALE_LOCK_AGE=<seconds>.
  4) Move SPM's scratch path off a network filesystem if the path above lives on NFS/SMB:
     swift build --scratch-path /tmp/innodi-cache  (NFS and SMB are not safe by default — see lock-safety.md).
```

Field meanings:

- **path**: the lock file the coordinator was waiting on. Inspect it
  with `cat` to see the JSON metadata if needed.
- **waited**: total seconds the coordinator polled for the lock.
- **holder pid**: PID written by the holding process. If it is `0` or
  the field is missing, the lock metadata was unreadable — most often a
  truncated lock from an interrupted run.
- **holder age**: seconds since the lock was created or modified, based
  on the file's modification time.
- **boot id**: when present, identifies the OS boot during which the
  lock was created. A mismatch with the current boot ID is conclusive
  evidence the holder is no longer running, and the coordinator will
  remove the lock without consulting the PID.
- **note**: appears only when a stale lock was recovered earlier in the
  same run but contention persisted afterwards.

## Recovering from a stuck lock

In order of decreasing safety:

1. **Wait and retry.** A live concurrent build will release the lock
   when it finishes. Subsequent runs read the cached result instead of
   re-running validation.
2. **Increase the wait window** with `INNODI_LOCK_TIMEOUT=180`.
3. **Remove the lock manually** if the holder PID does not exist
   (`kill -0 <pid>` returns `ESRCH`):

   ```sh
   rm '<path-from-diagnostic>'
   ```

   The coordinator will detect the missing file on the next run and
   resume normally. Do not delete a lock whose holder is alive — the
   in-progress validation will then write a partial result that the
   cache treats as authoritative.
4. **Reduce the stale threshold** with `INNODI_STALE_LOCK_AGE=10` if
   the holder has been frozen for longer than the new threshold and
   the PID check is unreliable (rare).

## Permission and disk-full failures

`open(O_CREAT | O_EXCL)` can fail for reasons other than contention.
The coordinator surfaces those as `POSIXLockError`, with the
symbolic `errno` name embedded in the message:

```text
Failed to acquire validation lock at '/…/lock' (errno: 13 EACCES).
The directory is read-only or this process lacks write permission.
Set SPM `--scratch-path` (or DerivedData) to a writable, local filesystem.
```

Common cases:

- **EACCES / EROFS** — the scratch path is read-only. Most often
  caused by sandboxed CI workers writing to a mounted toolchain
  archive. Fix by passing `--scratch-path` explicitly.
- **ENOSPC** — disk is full. Free space on the volume that backs the
  scratch path.
- **ENOENT / ENOTDIR** — the scratch directory was deleted between
  resolution and lock attempt. Re-running with a clean build fixes it.

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `INNODI_LOCK_TIMEOUT` | `30` | Seconds the coordinator polls the lock before giving up. |
| `INNODI_STALE_LOCK_AGE` | `30` | Seconds after which an apparently-orphaned lock is eligible for recovery. |
| `INNODI_ALLOW_UNSAFE_LOCK` | unset | Set to `1`, `true`, `yes`, or `on` to bypass the unsafe-filesystem fail-fast (NFS, SMB/CIFS, WebDAV, FUSE). The coordinator still emits a one-line warning so the bypass is auditable in build logs. |

`INNODI_LOCK_TIMEOUT` and `INNODI_STALE_LOCK_AGE` accept positive
floating-point seconds. Unparseable values fall back to the default
and emit a stderr warning so the misconfiguration surfaces at the
first build.

## See also

- `<doc:Validation>` — overall validation pipeline.
- `<doc:DiagnosticsGuide>` — message-ID catalog for macro and build
  diagnostics.
- `Sources/InnoDIBuildSupport/ValidationCoordinator+Locking.swift` —
  the implementation, including the boot-ID check used during stale
  recovery.
