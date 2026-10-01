# Lock 안전성

InnoDI의 빌드 시점 validation coordinator가 동시에 도는 빌드 사이에서 실행을
어떻게 직렬화하는지, 그리고 실패했을 때 무엇을 해야 하는지 설명합니다.

## 개요

`swift build`와 Xcode가 InnoDI build plugin을 병렬로 호출하면(예: Xcode 창을
열어 둔 채 CLI 빌드를 하는 경우), plugin은 live DAG 검증 단계를
*signature*(모든 컨테이너 소스의 정규화된 hash)마다 POSIX lock 하나로
직렬화합니다. lock은 SwiftPM plugin work directory 안의 파일에 대해
`open(O_CREAT | O_EXCL | O_RDWR)`로 얻습니다. 이 디렉터리는 활성 SPM
scratch/derived-data 위치 아래에 만들어집니다.

이 문서는 그 lock이 파일시스템에 요구하는 조건, 오류 메시지의 의미, 빌드가
lock을 얻지 못했을 때의 복구 방법을 설명합니다.

## 파일시스템 요구 사항

`O_CREAT | O_EXCL`은 Apple과 Linux가 기본으로 제공하는 로컬 파일시스템에서
**원자적**입니다.

| 파일시스템 | 상태 | 비고 |
|---|---|---|
| APFS | ✅ 지원 | 기본 macOS / iOS simulator 빌드. |
| HFS+ | ✅ 지원 | |
| ext4 / btrfs / xfs | ✅ 지원 | Linux SPM 빌드. |
| tmpfs | ✅ 지원 | CI에서 SPM scratch path로 자주 쓰입니다. |
| **NFS** | ❌ 기본적으로 미지원 | 감지기가 mount 버전과 lock 의미를 안정적으로 구별할 수 없어, InnoDI는 NFS mount를 안전하지 않다고 분류합니다. scratch path를 로컬 볼륨으로 옮기거나 `INNODI_ALLOW_UNSAFE_LOCK=1`로 opt-in하세요. |
| **SMB / CIFS** | ❌ 미지원 | 원자성이 보장되지 않습니다. |
| **WebDAV** | ❌ 미지원 | Darwin `webdav` 볼륨은 네트워크 기반이라 기본적으로 안전하지 않다고 분류됩니다. |
| **FUSE / macFUSE / osxfuse** | ❌ 기본적으로 미지원 | FUSE 파일시스템은 driver마다 다르므로, InnoDI는 이를 안전하지 않다고 분류해 운영자가 의도적으로 opt-in하게 합니다. |
| Linux overlayfs / AUFS | ❌ 기본적으로 미지원 | 감지기가 안전하지 않다고 분류합니다. 로컬에 bind mount한 scratch path를 쓰세요. |

derived-data 디렉터리가 네트워크 공유 위에 있는 곳에서 build plugin을 돌려야
한다면 SPM scratch path를 옮기세요.

```sh
swift build --scratch-path /tmp/innodi-cache
```

plugin 상태 디렉터리는 그 scratch path를 따라갑니다. InnoDI는 더 이상 build
plugin의 lock/cache 상태를 `<package>/.build/innodi-dag-validation`에 쓰지
않으므로, 안전하지 않은 package root에서는 로컬 `--scratch-path`가 문서화된
복구 경로입니다.

InnoDI는 실행을 시작할 때마다 lock 디렉터리 아래의 파일시스템을 자동으로
감지합니다. 안전하지 않은 파일시스템이면 coordinator는
[안전하지 않은 파일시스템에서의 거부](#안전하지-않은-파일시스템에서의-거부)에
나온 진단 블록과 함께 즉시 실패합니다. 검사를 우회하려면
`INNODI_ALLOW_UNSAFE_LOCK=1`을 설정하세요(위험은 직접 감수합니다).

## 안전하지 않은 파일시스템에서의 거부

자동 감지기가 lock 디렉터리를 `nfs`, `smbfs`, `cifs`, `webdav`, 또는 FUSE 기반
파일시스템으로 분류하면, coordinator는 다음 stderr 블록을 내고 상태 `1`로
종료합니다.

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

감지기가 `unknown`(InnoDI가 아직 모르는 파일시스템)을 반환하면 coordinator는
한 줄 경고를 내고 계속 진행합니다. 모르는 파일시스템에서 막지 않는 이유는,
가장 흔한 원인이 아직 표에 넣지 못한 새롭고 완전히 안전한 파일시스템이기
때문입니다. 아직 분류하지 않은 파일시스템은
`Sources/InnoDIBuildSupport/FilesystemTypeDetector.swift`에서 추적합니다.
사용하는 파일시스템에 명시적인 처리가 필요하면 issue를 열어 주세요.

## Lock timeout 진단 읽기

coordinator가 lock을 기다리다 포기하면(기본 `30s`, `INNODI_LOCK_TIMEOUT`으로
변경), plugin은 구조화된 stderr 블록을 냅니다.

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

필드 의미:

- **path**: coordinator가 기다린 lock 파일입니다. 필요하면 `cat`으로 열어 JSON
  metadata를 확인하세요.
- **waited**: coordinator가 lock을 polling한 총 시간(초)입니다.
- **holder pid**: lock을 가진 프로세스가 기록한 PID입니다. `0`이거나 필드가
  없으면 lock metadata를 읽을 수 없었다는 뜻이며, 대개 중단된 실행이 남긴 잘린
  lock입니다.
- **holder age**: 파일 수정 시각을 기준으로, lock이 만들어지거나 수정된 뒤
  지난 시간(초)입니다.
- **boot id**: 있으면 lock이 만들어진 OS boot를 식별합니다. 현재 boot ID와
  다르면 holder가 더 이상 실행 중이 아니라는 확실한 증거이며, coordinator는
  PID를 확인하지 않고 lock을 지웁니다.
- **note**: 같은 실행에서 오래된 lock을 먼저 복구했는데도 경합이 계속됐을 때만
  나타납니다.

## 멈춘 lock에서 복구하기

안전한 순서대로:

1. **기다렸다가 다시 시도하세요.** 동시에 도는 살아 있는 빌드는 끝나면 lock을
   놓습니다. 이후 실행은 검증을 다시 돌리지 않고 cache된 결과를 읽습니다.
2. `INNODI_LOCK_TIMEOUT=180`으로 **대기 시간을 늘리세요**.
3. holder PID가 없으면(`kill -0 <pid>`가 `ESRCH`를 반환하면) **lock을 직접
   지우세요**.

   ```sh
   rm '<path-from-diagnostic>'
   ```

   coordinator는 다음 실행에서 파일이 없어진 것을 감지하고 정상적으로
   계속합니다. holder가 살아 있는 lock은 지우지 마세요. 진행 중인 검증이 부분
   결과를 쓰고, cache가 그 결과를 권위 있는 결과로 취급하게 됩니다.
4. holder가 새 threshold보다 오래 멈춰 있고 PID 확인을 믿을 수 없을 때(드문
   경우) `INNODI_STALE_LOCK_AGE=10`으로 **stale threshold를 낮추세요**.

읽기 전용 진단을 하려면 다음을 실행하세요.

```sh
swift run InnoDI-DependencyGraph --diagnose-lock /tmp/innodi-cache
```

scratch 디렉터리나 진단에 나온 plugin 상태 디렉터리를 넘기세요. 명령은 그 경로
아래의 InnoDI lock 파일을 재귀적으로 찾습니다.

## 권한 오류와 디스크 부족

`open(O_CREAT | O_EXCL)`은 경합이 아닌 이유로도 실패할 수 있습니다.
coordinator는 이를 `POSIXLockError`로 보고하며, 메시지에 기호 `errno` 이름을
넣습니다.

```text
Failed to acquire validation lock at '/…/lock' (errno: 13 EACCES).
The directory is read-only or this process lacks write permission.
Set SPM `--scratch-path` (or DerivedData) to a writable, local filesystem.
```

흔한 경우:

- **EACCES / EROFS** — scratch path가 읽기 전용입니다. sandbox된 CI worker가
  mount된 toolchain archive에 쓰려 할 때 가장 흔합니다. `--scratch-path`를
  명시적으로 넘겨 고치세요.
- **ENOSPC** — 디스크가 가득 찼습니다. scratch path가 있는 볼륨의 공간을
  확보하세요.
- **ENOENT / ENOTDIR** — 경로를 확인한 뒤 lock을 시도하기 전에 scratch
  디렉터리가 지워졌습니다. clean build로 다시 실행하면 해결됩니다.

## 환경 변수

| 변수 | 기본값 | 용도 |
|---|---|---|
| `INNODI_LOCK_TIMEOUT` | `30` | coordinator가 포기하기 전에 lock을 polling하는 시간(초). |
| `INNODI_STALE_LOCK_AGE` | `30` | 버려진 것으로 보이는 lock을 복구 대상으로 보는 기준 시간(초). |
| `INNODI_ALLOW_UNSAFE_LOCK` | 설정 안 함 | `1`, `true`, `yes`, `on` 중 하나로 설정하면 안전하지 않은 파일시스템(NFS, SMB/CIFS, WebDAV, FUSE)에서의 즉시 실패를 우회합니다. 우회 사실이 빌드 로그에 남도록 coordinator는 여전히 한 줄 경고를 냅니다. |

`INNODI_LOCK_TIMEOUT`과 `INNODI_STALE_LOCK_AGE`는 양의 부동소수점 초를
받습니다. 해석할 수 없는 값은 기본값으로 돌아가고 stderr 경고를 내므로, 잘못된
설정은 첫 빌드에서 드러납니다.

## See also

- `<doc:Validation>` — 전체 검증 pipeline.
- `<doc:DiagnosticsGuide>` — 매크로와 빌드 진단의 message-ID 카탈로그.
- `Sources/InnoDIBuildSupport/ValidationCoordinator+Locking.swift` — 오래된
  lock을 복구할 때 쓰는 boot-ID 검사를 포함한 구현.
