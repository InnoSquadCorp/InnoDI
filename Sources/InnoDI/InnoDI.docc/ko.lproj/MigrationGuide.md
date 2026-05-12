# 마이그레이션 가이드

버전별 업그레이드 노트입니다. 릴리스 시점의 전체 하이라이트와
breaking change 표는
[`RELEASING.md`](https://github.com/InnoSquadCorp/InnoDI/blob/main/RELEASING.md)
를 참고하세요. 이 문서는 같은 정보를 **컨슈머가 무엇을 바꿔야 하는가**를
기준으로 재구성한 것입니다.

## 개요

| From → To | 변경 카테고리 | 필요한 작업 |
|---|---|---|
| 1.x → 2.x | Validation 정책 강화 | 매크로 테스트를 다시 실행하고, 더 엄격해진 validator가 새로 발생시키는 진단을 해결하세요. |
| 2.x → 3.x | OSS baseline + governance | 코드 변경은 필요 없습니다. 내부 릴리스 도구가 legacy notes 대신 `RELEASING.md` 섹션을 읽도록 갱신하세요. |
| 3.x → 4.0 | 공개 계약 정리 | `@SubContainer`의 새로운 `withNames:`/`with:`/`bindings:` 매트릭스를 채택하세요. `_LazyCell` import를 중단하고, `_storage_` / `_override_sub_` / `_innoDISubBuild_` 예약 prefix로 시작하는 컨테이너 멤버의 이름을 변경하세요. |
| 4.0 → 4.1 | DX 강화 | `@SubContainer(... withNames:)` 마이그레이션은 필수 아닙니다. 스택드 peer-macro 컨텍스트에서는 `withNames:`를 계속 쓰고, Swift 타입 체커가 key-path를 받아주는 단일 매크로 사이트는 `with:`로 옮기세요. lock-timeout stderr 블록을 파싱하는 곳은 구조화된 필드를 읽도록 갱신하세요. |
| 4.1 → 4.2 | `@SubContainer` wiring 단순화 | 모든 `withNames:` 사이트를 `with:` key path로 교체하거나, 스택드 peer-macro 헬퍼를 manual/root 헬퍼 코드로 분리하세요. `withNames:`는 더 이상 공개 매크로 시그니처에서 받지 않습니다. |
| 4.2 → 4.3 | Feature-root 헬퍼 통합 | 새 SwiftUI feature-root 헬퍼는 스택드 `@DIFeatureRoot` 대신 `@SubContainer(featureRoot:)` 또는 `featureRoots:`로 옮기세요. `@DIFeatureRoot`는 호환성 용도로 deprecated 상태로 남습니다. |
| 4.x → 5.0 (예정) | `@GenerateMock` 한정 | RFC 0001이 계획대로 GA로 들어옵니다. RFC 0002는 4.2의 wiring 단순화로 이미 적용됐습니다. |

이후 본문은 사용자가 보통 필요로 하는 순서대로 — 먼저 4.1 → 4.2 wiring
단순화, 그 다음 4.0 → 4.1 운영 강화, 그 다음 5.0의 예정 surface와
이전 버전 hop — 으로 펼쳐집니다.

---

## 4.2 → 4.3

### Feature-root 헬퍼를 `@SubContainer`로 이동

```swift
// Before
@SubContainer(scope: .shared, with: [\.config])
@DIFeatureRoot(DashboardRootView.self)
@DIFeatureRoot(DashboardShellView.self, as: "dashboardShell")
var dashboard: DashboardContainer

// After
@SubContainer(
    scope: .shared,
    with: [\.config],
    featureRoots: [
        FeatureRoot(DashboardRootView.self),
        FeatureRoot(DashboardShellView.self, as: "dashboardShell")
    ]
)
var dashboard: DashboardContainer
```

단일 root view만 필요한 일반 케이스는 더 짧은 형태를 권장합니다.

```swift
@SubContainer(scope: .shared, with: [\.config], featureRoot: DashboardRootView.self)
var dashboard: DashboardContainer
```

생성되는 헬퍼 이름은 그대로입니다. default root는 여전히
`dashboardRootView()`를 만들고, `"dashboardShell"` alias는
`dashboardShellRootView()`를 만듭니다. 차이는 소유권입니다. 헬퍼 생성이
이제 `@DIContainer` member expansion에 속하므로 같은 프로퍼티에
`@SubContainer`와 다른 peer macro를 스택할 필요가 없습니다.

`@DIFeatureRoot`는 deprecated compatibility macro로 계속 제공됩니다. 기존
call site를 옮기는 동안에만 유지하고, 새 코드는 `featureRoot:` /
`featureRoots:`를 사용하세요.

---

## 사내 v1-v3 사용자가 4.x로 옮길 때

InnoSquad나 뱅크샐러드식 monorepo에서 초기 InnoDI를 이미 쓰고 있었다면,
4.x 업그레이드는 단순한 package version bump가 아니라 validation과 공개
계약 정리로 다루는 편이 안전합니다.

권장 순서:

1. 4.x package dependency를 추가하고, 먼저 DAG plugin 없이 한 target을
   빌드합니다.
2. macro diagnostic을 먼저 해결합니다: reserved generated prefix, missing
   factory, concrete opt-in, container type 내부 custom `init` 선언.
3. nested container wiring을 `with:` 또는 `bindings:`로 옮긴 뒤 hierarchy
   validator를 켭니다.
4. target에 `InnoDIDAGValidationPlugin`을 붙이고, derived data가 shared
   volume에 있다면 `--scratch-path`를 local disk로 옮깁니다.
5. `Tools/check-docs-code-blocks.sh`와 strict-concurrency test를 repo gate에
   넣어 예제와 내부 튜토리얼이 drift되지 않게 합니다.

기존 call site를 보존하려고 InnoDI 위에 runtime service locator를 덮지
마세요. 그렇게 하면 4.x 라인의 핵심 가치인 reviewability와 graph validation을
잃습니다. 경계 예시는 <doc:AntiPatterns>를 참고하세요.

---

## 4.1 → 4.2

### `@SubContainer(... withNames:)` 제거

```swift
// Before
@SubContainer(scope: .shared, withNames: ["config", "apiClient"])
var feature: FeatureContainer

// After
@SubContainer(scope: .shared, with: [\.config, \.apiClient])
var feature: FeatureContainer
```

`withNames:`는 더 이상 공개 `@SubContainer` 시그니처, 매크로 파서,
build-support hierarchy validation 어디에도 존재하지 않습니다. 대부분의
사이트는 `with:`로 직접 옮겨야 합니다. key-path 자동완성과 IDE 리팩터링
시 rename 안전성이 그 이유입니다.

이전에 `@SubContainer`를 다른 peer 매크로와 같은 프로퍼티에 스택해서
Swift의 key-path 순환 참조 한계를 우회하기 위해 `withNames:`를 썼다면,
문자열 escape hatch를 유지하지 말고 헬퍼 생성을 분리하세요. 예를 들어
`@SubContainer(scope:with:)`를 컨테이너 멤버에 두고, 생성된 자식
컨테이너로부터 root view를 만드는 작은 extension 메서드를 추가합니다.

`bindings:`는 자식 라벨과 부모 멤버 이름을 명시적으로 다시 매핑하는
형태로 그대로 남아 있고, `with: []`는 명시적 빈 same-name subset으로
`Child()`를 호출합니다.

### Validation 플러그인 state 디렉토리

DAG validation build plugin은 이제 lock/cache 상태를
`<package>/.build` 대신 SwiftPM의 `pluginWorkDirectoryURL` 하위에
저장합니다. 이렇게 해서 호출자가
`swift build --scratch-path /tmp/innodi-cache`로 SwiftPM scratch 경로를
옮기면 unsafe한 패키지 루트 파일시스템에서 상태가 분리됩니다.

lock 진단을 보려면 검사하고 싶은 scratch/플러그인 state 디렉토리를
`swift run InnoDI-DependencyGraph --diagnose-lock <path>`에 넘기세요.

### 문서 스니펫 게이트

릴리스와 PR 게이트가 이제 `Tools/check-docs-code-blocks.sh`를
실행합니다. `<!-- innodi:compile -->` 마커가 바로 앞에 붙은 Swift fenced
블록만 컴파일되므로, 설명용 스니펫은 마커 없이 두고 contract 스니펫이
어긋나면 CI가 실패합니다.

---

## 4.0 → 4.1

### Lock-timeout stderr 포맷 변경

validation coordinator의 lock-timeout 진단이 한 줄짜리 메시지에서
구조화된 다중 행 블록으로 바뀌었습니다. 이전 문구
(`Timed out waiting for validation coordinator lock at '...'`)를
grep하던 CI 스크립트는 다음 구조 필드로 옮기세요.

```text
path:        <the lock path>
waited:      <seconds>s
holder pid:  <pid>
holder age:  <seconds>s
boot id:     <id>
```

종료 코드 `1`과 metrics artifact의 `reasonCodes` 배열만 읽고 있다면
변경할 필요는 없습니다.

### 파일시스템 안전 가드 — unsafe scratch 경로 opt-in

빌드가 SPM scratch 디렉토리를 **NFS**, **SMB**, **CIFS**, **WebDAV**,
또는 일부 FUSE 기반 파일시스템 위에 두고 있다면, coordinator가 이제
lock 획득을 거부합니다. 둘 중 하나를 선택하세요.

1. scratch 경로 이동: `swift build --scratch-path /tmp/innodi-cache`
2. unsafe 경로 opt-in: `INNODI_ALLOW_UNSAFE_LOCK=1 swift build`
   (coordinator는 여전히 경고를 출력하므로 bypass는 CI 로그에서
   감사 가능합니다.)

로컬 APFS / HFS+ / ext4 / btrfs / xfs / tmpfs 빌드는 변경이 필요 없습니다.

### 매크로 합성 `fatalError` 트랩 제거

`@Provide(.transient)`가 잘못된 입력(factory 누락, 와일드카드 파라미터,
미지정 scope)에 대해 합성하던 런타임 `fatalError("...")`에 의존했다면,
이 트랩은 사라졌다는 점을 인지하세요. 같은 조건은 이제 build-time
진단과, accessor가 빠져나간 프로퍼티에서 발생하는 Swift 컴파일러의
"stored property has no initial value" 에러를 발생시킵니다.

이 트랩을 런타임 게이트로 의존하던 호출자에게만 source-incompatible
하지만 — 그런 호출자는 거의 없을 것으로 보지만 — 완전성을 위해 적어둡니다.

### `ValidationReasonCode.unsafeFilesystem` (artifact 변경)

validation metrics JSON artifact를 파싱한다면 `unsafe-filesystem`
케이스를 추가하세요. FS 가드가 fail-fast할 때 `reasonCodes` 배열에
나타납니다. 필드가 `[String]`이고 항상 open이었기 때문에 schema bump는
없습니다.

### 새 운영 도구

쓸 의무는 없지만 유용할 수 있는 두 가지 추가:

- `swift run InnoDI-DependencyGraph --diagnose-lock [<scratch-path>]` —
  파일시스템 클래스, 환경 변수 override, 활성/stale lock 파일과 메타데이터를
  출력합니다. CI에서 발생하는 `lock-contention-timeout`의 runbook입니다.
- `Tools/check-no-fatalerror-in-macros.sh` — 두 개의 allow-list runtime
  invariant 외부에서 매크로 plugin 소스에 새 `fatalError(...)`가
  들어오면 CI를 실패시키는 레포지토리 로컬 가드입니다.

---

## 4.x → 5.0 (예정)

5.0은 추가형 RFC들이 GA로 들어오는 첫 번째 메이저 릴리스입니다. 원래
짝지어 있던 wiring 단순화는 이미 5.0 이전에 적용됐습니다.

| RFC | 내용 | 컨슈머 영향 |
|---|---|---|
| [0001 — `@GenerateMock`](https://github.com/InnoSquadCorp/InnoDI/blob/main/docs/rfcs/0001-macro-mock-generation.md) | 새 매크로 | 추가형. 마이그레이션 불필요, 도입 선택. |
| [0002 — SubContainer wiring 단순화](https://github.com/InnoSquadCorp/InnoDI/blob/main/docs/rfcs/0002-subcontainer-wiring-simplification.md) | `withNames:` 제거 | 5.0 이전에 이미 적용. 컨슈머는 `with:` 또는 `bindings:`만 사용해야 합니다. |

프로젝트가 이미 `withNames:` 없이 빌드된다면, 5.0은 SubContainer wiring
관점에서 no-op입니다.

---

## 3.x → 4.0

자세한 내용은 [`RELEASING.md` § 4.0.0](https://github.com/InnoSquadCorp/InnoDI/blob/main/RELEASING.md)
을 참고하세요. 영향이 큰 항목은 다음과 같습니다.

- 당시의 새 `@SubContainer` wiring 매트릭스: `with:` / `withNames:` /
  `bindings:` 와 implicit 형태. 현재 릴리스는 `with:` / `bindings:`만
  받습니다. 멤버마다 정확히 하나의 spelling을 선택하세요 (validator가
  conflict를 진단합니다).
- `Lazy<T>`와 `Provider<T>`는 의도적으로 non-`Sendable` deferred
  handle이며 컨테이너의 원본 isolation 도메인에 머물러야 합니다.
- 이전에 공개되어 있던 `_LazyCell<T>` 런타임 헬퍼는 제거됐습니다.
  매크로는 이제 합성된 initializer 안에 로컬 `_InnoDIDeferredCell<T>`를
  emit합니다. downstream 코드는 어느 심볼에도 의존해서는 안 됩니다.
- `_storage_`, `_override_sub_`, `_innoDISubBuild_`,
  `_innoDIUnresolvedDependency`, `_subBuildCell_`, `_lazyCell_`,
  `_lazySelfForSub`로 시작하는 컨테이너 멤버 이름은 이제
  `container.reserved-name-prefix`로 거부됩니다. 그런 멤버는 이름을
  변경하세요.

---

## 2.x → 3.x

Validation 강화만 있고 공개 API churn은 없습니다. 3.x 프로젝트가 이미
경고 없이 validator를 통과하고 있다면, 2.x에서 업그레이드할 때 코드 변경은
필요 없습니다 — 더 엄격해진 validator가 노출하는 진단만 처리하면 됩니다.

---

## 1.x → 2.x

가장 오래된 아카이브 마이그레이션입니다. 당시 노트는 `RELEASING.md`의 git
history를 참고하세요. 아직 1.x를 쓰고 있다면, 점진적 업그레이드보다 한
번에 4.1까지 올리는 경로를 권장합니다 — 4.1의 진단 surface가 1.x나 2.x
보다 훨씬 풍부합니다.

---

## 함께 보기

- <doc:lock-safety> — 파일시스템 안전 정책과 lock-timeout 진단 레퍼런스.
- <doc:DiagnosticsGuide> — 모든 진단 ID와 원인/조치.
- <doc:Validation> — 전체 validation 파이프라인과 각 진단이 어디서
  발생하는지.
