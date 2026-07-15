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
| 4.x → 5.0 (미출시) | 공개 계약 강화 | `concrete:`와 `@DIFeatureRoot`를 제거하고, 지원 선언 경계·MainActor 격리·검증·Graph JSON v2 변경에 맞춰 마이그레이션하세요. `@GenerateMock`는 experimental 상태를 유지합니다. |

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

4.3에서는 `@DIFeatureRoot`를 deprecated compatibility macro로 유지했지만,
InnoDI 5.0에서는 제거합니다. 업그레이드하기 전에 남은 call site를 모두
`featureRoot:` / `featureRoots:`로 옮기세요.

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
- `Tools/check-no-fatalerror-in-macros.sh` — 매크로 plugin 소스에 직접적인
  `fatalError(...)`가 하나라도 들어오면 CI를 실패시키는 레포지토리 로컬
  가드입니다. 런타임 invariant 경로는 숨겨진 `_innoDITrap` entry point를
  사용합니다.

---

## 4.x → 5.0 (예정)

5.0은 매크로 surface를 더 늘리기 전에 compiler와 graph의 공개 계약을
복구합니다. 원래 함께 계획했던 wiring 단순화는 이미 적용됐으며, major
release라는 이유만으로 experimental 기능을 자동 GA로 올리지 않습니다.

| 영역 | 예정된 컨슈머 영향 |
|---|---|
| `concrete:` | 인자를 삭제하세요. 선언된 property type이 concrete storage와 existential storage를 결정합니다. |
| `@DIFeatureRoot` | `@SubContainer(featureRoot:)` 또는 `featureRoots:`로 교체하세요. |
| 선언 종류 | 5.0 container/component는 file scope 또는 비제네릭 nominal 안의 비제네릭 struct를 사용하세요. 지원하지 않는 선언 종류, local scope, 명시적인 `private` container에는 전용 진단이 발생합니다. 같은 파일에서 mount하려면 `fileprivate`를 사용하거나 private namespace 안에 default-access container를 두세요. |
| `@Provide` 선언 | 지원되는 `@DIContainer`의 고유한 unescaped 이름을 가진 직접적이고 평범한 stored instance `var`에 `@Provide`를 정확히 하나만 두세요. 중복 provider attribute나 property 이름, backtick-escaped 이름, `let`, computed/observed accessor, storage modifier, property wrapper, conditional/unknown attribute, setter access control, source에 직접 쓴 모든 property-level actor attribute(`@MainActor` 포함), standalone, 간접 nested 사용을 제거하세요. Actor 격리는 `@DIContainer(mainActor: true)`로 요청하고 `_InnoDIProvideAccessor`를 직접 붙이면 안 됩니다. |
| `@SubContainer` 선언 | 지원되는 parent `@DIContainer`의 unescaped 이름을 가진 직접적이고 평범한 stored instance `var`에 `@SubContainer`를 정확히 하나만 두세요. 완전한 child 선언을 `#if` 밖으로 옮기고 경쟁하는 wrapper와 storage/accessor modifier를 제거하며 `_InnoDISubContainerAccessor`를 직접 붙이지 마세요. |
| Provider 타입 | Opaque `some Protocol`은 existential `any Protocol`로, implicitly unwrapped `T!`는 명시적인 `T` 또는 `T?`로 바꾸세요. |
| 함수 값 `.input` | 생성 initializer 파라미터는 eager `T` 값을 유지하므로 `try` / `await` 인자 평가는 바뀌지 않습니다. 직접 표기한 non-optional function type은 자동 감지합니다. Typealias 뒤에 숨은 non-optional function type에는 literal `escaping: true`를 추가하세요. 이 옵션은 `.input` 밖에서 유효하지 않습니다. |
| 생성 source | `.shared`/`.transient` 멤버는 `factory:`, `asyncFactory:`, `Type.self`, property initializer 중 정확히 하나를 가져야 합니다. `.input`은 모두 없어야 하고 `with:`도 사용할 수 없습니다. |
| Sibling wiring | root `factory:`/`asyncFactory:` 클로저 리터럴의 고유한 unescaped 이름을 가진 파라미터 또는 `Type.self`와 `[\Self.config]`(또는 `[]`) 같은 canonical direct-member key path만 담은 literal 배열을 사용하세요. 일반, `Lazy<T>`, `Provider<T>` 파라미터 사이의 중복 effective 이름과 backtick-escaped dependency parameter 이름은 거부됩니다. 이름이 있는 container/module/typealias root, nested component, optional chaining, subscript, 계산된 원소는 거부됩니다. `with:`는 동기 provider만 지원합니다. 클로저가 아닌 factory와 property initializer는 sibling member를 읽을 수 없는 zero-edge source입니다. |
| Factory 효과 | async/throwing 효과를 명시하세요. `validateDAG: false`에서도 효과 호환성은 검증되며 `Type.self`/`with:`는 동기 전용입니다. |
| MainActor | `mainActor: true` component의 dependency conformer와 non-`Sendable` 생성 값의 생성·사용을 `@MainActor`에 두세요. actor 밖에서는 `MainActor.run` 안에서 생성하고 소비하고, direct `await`는 격리된 작업이 `Sendable` 결과를 반환할 때만 사용하세요. convenience initializer, `withOverrides`, child override, component mount의 override 적용 closure도 이제 `@MainActor`입니다. |
| Non-main-actor async `withOverrides` | 생성되는 `async` / `async throws` 메서드와 operation closure 타입은 `nonisolated(nonsending)`입니다. 호출자 actor executor를 유지하므로 임의의 non-`Sendable` container와 closure가 호출자 isolation 안에 머뭅니다. 동기 overload는 바뀌지 않습니다. |
| Validation | 동적 scope expression, conditional provider attribute, `#if` 안의 완전한 `@Provide` 또는 `@SubContainer` 멤버 선언을 지원되는 정적 형태로 바꾸세요. |
| 생성 이름 | `_storage_`, `_override_`, `_innoDI`, `_InnoDI`로 시작하는 direct container declaration, `InnoDI`라는 direct declaration, `Swift` 또는 `_Concurrency`라는 nested type/typealias, 그리고 `InnoDI`·`Swift`·`_Concurrency`라는 container, enclosing nominal, generic parameter 이름을 바꾸세요. 값 namespace의 `Swift`, `_Concurrency` 멤버는 계속 사용할 수 있습니다. `@DIEnvironmentBridge`는 target와 보이는 enclosing binder의 type namespace에서 `Swift`, `SwiftUI`, `InnoDISwiftUI`를 예약하고 struct/class/enum target만 지원하며, extension 대상 또는 extension 안의 대상은 더 이상 지원하지 않습니다. 5.0 후속 단계에서 target-scoped full-source preflight가 추가되기 전까지 attached macro가 볼 수 없는 enclosing declaration의 shadowing member, direct extension attachment, 독립적인 local bridge target도 피하세요. Direct extension과 local target은 Swift의 compiler-owned 제한이 먼저 발생할 수 있습니다. 예전 구현 로컬 이름인 `_resolved_`, `_task_`, `_lazyCell_`, `_subBuildCell_`, `_lazySelf`는 다시 사용할 수 있습니다. 공개 initializer와 operation label은 바뀌지 않습니다. |
| 생성 peer 충돌 | Direct `@Provide`와 `@SubContainer` property는 두 역할 전체에서 고유한 이름을 사용하세요. 서로 다른 이름도 같은 hidden peer로 변환될 수 있습니다. 예를 들어 async `X`와 `task_X`, 또는 child `X`와 `sub_X`, `sub_apply_X`, `apply_X`가 충돌할 수 있습니다. `container.generated-symbol-collision`이 가리키는 두 선언 중 하나를 바꾸세요. 진단에는 정확한 생성 symbol과 최초 source claim이 표시됩니다. |
| Graph JSON | module-qualified ID와 명시적 target/root-pruning scope를 갖는 schema v2로 consumer를 옮기세요. |
| `@GenerateMock` | experimental 상태를 유지하며, 5.0이 migration 또는 GA freeze를 뜻하지 않습니다. |

나머지 package를 compile하기 전에 공개 migration executable을 실행하세요.

```bash
swift run InnoDI-Migrate --root . --check
swift run InnoDI-Migrate --root . --write
swift run InnoDI-Migrate --root . --check
```

안전하게 자동 변경할 파일이 있으면 `--check`는 파일마다 `MIGRATE` record를
출력하고 exit code `1`로 종료합니다. `--write`는 첫 atomic file replacement 전에
전체 source tree를 parse하고 preflight하며 기존 UTF-8 BOM을 보존합니다. 소유권이
모호한 attribute, 지원하지 않는 legacy argument, parse error, source symlink,
동시에 변경된 source를 만나면 exit code `2`로 fail-closed합니다. Preflight
실패는 아무 파일도 쓰지 않습니다. Write 도중 감지한 변경이 있으면 tool 출력과
여전히 정확히 일치하는 파일만 rollback하므로 감지된 외부 편집은 덮어쓰지
않습니다. 소유권이 모호하면 먼저 attribute의 실제 owning module을 확인하세요.
InnoDI 소유 선언이라면 `@InnoDI.DIContainer`와 `@InnoDI.Provide`, 또는
`@InnoDI.SubContainer`와 `@InnoDISwiftUI.DIFeatureRoot`처럼 짝이 되는 macro
전체를 module-qualified 형태로 바꾼 뒤 다시 실행하세요. Scanner는 `.build`,
`.git`, `.swiftpm`, nested Git repository를 건너뜁니다. Nested repository도
바꿔야 한다면 해당 repository를 별도 `--root`로 지정하세요.

공개된 underscored `DIEnvironmentBridging` witness는 5.0에서 breaking rename이
적용됩니다. `_innodiEnvironmentBridgeModifier()`를
`_innoDIEnvironmentBridgeModifier()`로 바꾸세요. 예전 이름을 사용한 manual
conformance와 direct call을 모두 수정해야 합니다. Application code가 이 compiler
support requirement에 의존하지 않도록 `@DIEnvironmentBridge`와 공개
`.innodi(_:)` view API를 우선 사용하세요.

생성 conformance는 이제 protocol을
`InnoDISwiftUI.DIEnvironmentBridging`으로 표기합니다. 따라서 bridge target이나
보이는 type binder가 `InnoDISwiftUI`라는 이름이면 함께 바꿔야 합니다.

독립적인 `@DIEnvironmentBridge` target의 generated-name migration은 namespace를
구분합니다. `_InnoDIEnvironmentBridgeModifier`라는 direct nested nominal type,
protocol, typealias, static/class variable·function, enum case와
`_innoDIEnvironmentBridgeModifier`라는 direct instance variable 또는 parameter가
없는 instance function의 이름을 바꾸세요. Top-level `#if` branch에도 같은 규칙을
적용합니다. 대문자 이름의 instance value/function, 소문자 이름의 static/class
member와 parameter가 있는 overload, target·generic parameter 이름,
cross-namespace 선언, nested body 안의 선언은 bridge 합성과 충돌하지 않습니다.
Mapping은 direct `\EnvironmentValues.member` 또는
`\SwiftUI.EnvironmentValues.member`를 사용하세요. Alias, 다른 root, chain,
subscript는 더 이상 지원하지 않습니다. 다른 nominal 안에 중첩된 private target
또는 enclosing lookup component는 `fileprivate`나 default access로 바꾸세요.
File-scope private bridge target은 계속 지원합니다. `@DIContainer`도 붙은 target에는
container의 더 넓은 `_innoDI`·`_InnoDI` prefix 예약이 계속 적용됩니다. Generic
parameter pack을 선언한 target에서는 bridge를 떼고 일반 generic parameter 또는
non-generic adapter type을 사용하세요.

5.0에서는 component mounting marker를 isolation에 따라 분리합니다. 일반
component는 `InnoDI._InnoDIComponentMountable`에 계속 conform하고, container가
`mainActor: true`인 component는 대신
`InnoDI._InnoDIMainActorComponentMountable`에 conform합니다. Hierarchy root도
`InnoDI.DIHierarchyRootMarker`에 conform합니다. Module qualifier 때문에 consumer
module의 같은 이름 선언이 생성 conformance를 가로채지 못합니다. generic mounting
helper에는 `@MainActor` actor marker용 overload를 별도로 추가하고 override parameter를
`@MainActor (inout Component._InnoDIComponentOverrides) -> Void`로 선언하세요.
`_InnoDIComponentMountable`만 constraint로 사용하는 helper는 더 이상 main-actor
component를 받지 않습니다. non-`Sendable` mount 결과는 actor 밖으로 반환하지 말고
`@MainActor` caller나 `MainActor.run` block 안에서 계속 사용하세요.
Backtick으로 escape한 `@DIComponent` target은 unescaped Swift identifier로 이름을
바꿔 생성되는 `<Container>Dependencies` protocol 이름이 하나의 canonical spelling을
갖도록 하세요.

`mainActor: true`를 사용하지 않는 컨테이너의 비동기 `withOverrides` 작업은 호출자
isolation에 유지하세요. 생성되는 `async`와 `async throws` 메서드 및 operation
closure 타입은 `nonisolated(nonsending)`으로, container나 closure가 isolation
경계를 넘도록 요구하지 않고 호출자 actor executor를 유지합니다. 이 호출 경로를
위해 억지로 `Sendable`을 추가하지 마세요. 동기 overload는 바뀌지 않으며
`mainActor: true`의 모든 overload는 계속 `@MainActor`입니다.

5.0 채택 전에 class, actor, enum, protocol, extension 또는 generic
`@DIContainer` 선언과 함께 붙은 `@DIComponent`를 실질적으로 비제네릭인
struct 경계로 바꾸세요. 컨테이너 자체나 이를 감싸는 generic nominal 선언에
generic parameter나 generic `where` clause가 있으면 지원하지 않습니다.
런타임·타입별 상태는 명시적 protocol dependency나 `.input` 값으로 옮기세요.
extension 안에 중첩된 struct도 syntax-only macro가 대상의 generic 여부를
증명할 수 없으므로 file scope나 비제네릭 nominal로 이동해야 합니다. 함수,
closure, initializer, accessor, switch case, local block 같은 실행 스코프의
컨테이너는 해당 스코프의 generic 여부와 관계없이 file scope나 비제네릭
nominal 선언으로 옮기세요. generic 함수 안의 nested type이나
`@DIComponent` 같은 attached-extension macro를 함께 적용한 local container처럼
Swift 언어 자체가 허용하지 않는 위치에서는 Swift compiler 진단이 함께 나올
수 있습니다.
명시적인 `private` container는 같은 파일에서 mount할 경우 `fileprivate`로
바꾸거나, default access를 유지한 채 private namespace 안으로 옮기세요. 그래야
생성된 child-mount API가 sibling container에서 접근 불가능해지는 일을 막습니다.

모든 provider를 평범한 stored instance 변수로 옮기세요.

```swift
// 이전: observed/static/accessor-backed provider 선언은 지원하지 않습니다.
@Provide(.shared, factory: Service(), concrete: true)
static var service: Service {
    didSet { audit(service) }
}

// 이후
@Provide(.shared, factory: Service(), concrete: true)
var service: Service
```

`_InnoDIProvideAccessor`를 직접 붙이지 마세요. 지원되는 provider member에 대해
컨테이너 매크로가 합성하는 내부 accessor 지원입니다.
프로퍼티마다 `@Provide` attribute는 하나만 남기고 모든 direct provider property와
root factory dependency parameter에 고유한 unescaped effective 이름을 사용하세요.
Direct `@Provide`와 `@SubContainer` property는 하나의 managed-member identity
namespace를 공유하므로 역할을 가로질러서도 이름이 고유해야 합니다. Source 이름이
서로 달라도 `container.generated-symbol-collision`이 같은 hidden peer를 가리키면
둘 중 하나의 이름을 바꾸세요. `@SubContainer` property 이름도 unescaped여야 하며 `#if` 밖의 직접적이고
평범한 stored instance variable에 정확히 한 번 선언해야 합니다.
`_InnoDISubContainerAccessor`를 직접 붙이지 마세요. Parent container가 소유합니다.
Compiler-support accessor와
다른 property wrapper를 의도적으로 위조해 함께 붙이면 안정적인 InnoDI misuse
진단과 함께 Swift 자체의 structural diagnostic도 발생할 수 있습니다.

Provider 선언에서 property wrapper, conditional/unknown attribute,
`private(set)` 같은 setter access modifier, source에 직접 쓴 모든 property-level
global-actor attribute를 제거하세요. 여기에는 `@MainActor`도 포함됩니다. Actor
격리는 대신 `@DIContainer(mainActor: true)`로 요청하세요. Provider 선언과
accessor에 InnoDI가 생성한 격리 attribute는 내부 compiler support입니다. 완전한
provider 멤버는 `#if` 밖으로 옮기고 factory 또는 주입 구현 내부에서 분기하세요.

생성 storage에 의존하기 전에 provider property type을 정규화하세요.

```swift
// 이전: opaque와 implicitly unwrapped provider type은 지원하지 않습니다.
@Provide(.shared, factory: LiveService())
var service: some ServiceProtocol

@Provide(.input)
var delegate: ServiceDelegate!

// 이후
@Provide(.shared, factory: LiveService())
var service: any ServiceProtocol

@Provide(.input)
var delegate: ServiceDelegate?

typealias Handler = @Sendable () -> Void

// 직접 함수 표기는 자동 감지하며, alias에는 명시적 opt-in이 필요합니다.
@Provide(.input, escaping: true)
var handler: Handler
```

Input initializer 파라미터는 계속 선언 타입의 eager 값입니다. 호출자는
`throwingValue: try makeValue()`와 `asyncValue: await makeValue()`를 그대로 전달할
수 있고, Swift가 initializer 호출 전에 식을 평가합니다. `escaping:`은 literal
Bool이어야 하며 non-optional function-valued `.input`에만 적용됩니다. 명백한
nonfunction/optional-function 형태는 `provide.escaping-nonfunction-type`, 다른
scope는 `provide.escaping-invalid-scope`를 받습니다. 매크로는 identifier/member
alias를 보수적으로 허용하므로 `escaping: true`를 붙인 alias가 실제 non-optional
function type으로 해석되지 않으면 Swift 자체 진단이 추가될 수 있습니다.

Edge를 바꾸기 전에 생성 source를 점검하세요. `.shared` 또는 `.transient` 멤버는
`factory:`, `asyncFactory:`, `Type.self`, property initializer 중 정확히 하나를
선언해야 합니다. `.input` 멤버는 모두 선언하지 않고 `with:`도 사용하지 않습니다.
네 source는 함께 더하는 설정이 아니라 서로 배타적인 대안입니다.

Sibling member에 의존하는 생성 source는 두 가지 명시적 edge 형태 중 하나로
바꾸세요.

```swift
@DIContainer
struct FeatureContainer {
    @Provide(.input)
    var apiClient: APIClient

    // 이전: sibling을 읽는 opaque zero-edge 표현식이므로 허용되지 않습니다.
    @Provide(.shared, factory: Repository(client: apiClient), concrete: true)
    var repository: Repository

    // 이후: root 클로저의 이름 있는 파라미터가 sibling edge를 선언합니다.
    @Provide(.shared, factory: { (apiClient: APIClient) in
        Repository(client: apiClient)
    }, concrete: true)
    var migratedRepository: Repository
}
```

`Type.self`와 literal `with:` key-path 배열은 명시적 autowiring 형태로 계속
지원됩니다. 각 항목은 `with: [\Self.apiClient]`처럼 정확히 canonical
direct-member 표기 `\Self.member`를 사용해야 하며 `with: []`도 유효합니다. 이름이
있는 container, module-qualified, typealias root와 nested component, optional
chaining, subscript, 계산된 원소는 거부됩니다. 이 형태는 동기 생성 provider만
참조할 수 있습니다. 클로저가 아닌 `factory:` 표현식이나 property initializer는
opaque zero-edge source로만 허용되며, 이 경우 qualified global/static 생성 symbol을
사용하세요.

효과는 edge에서 추론하지 않습니다. 이름 있는 root 파라미터나 `with:` key path가
async provider를 가리키면 `asyncFactory:`를 사용하고, provider가 throw할 수 있으면
클로저를 `async throws`로 선언하세요. `validateDAG: false`로 이 매트릭스를
우회할 수 없습니다. `Type.self`/`with:`는 더 엄격한 동기 전용 형태로 `async`나
`async throws` provider를 참조할 수 없습니다.

이 섹션은 구현이 진행되는 동안의 migration 개요입니다. 남은 진단,
codemod 명령, before/after 예제는 5.0.0 tag 전 release blocker입니다.

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
- 4.x에서는 `_storage_`, `_override_sub_`, `_innoDISubBuild_`,
  `_innoDIUnresolvedDependency`, `_subBuildCell_`, `_lazyCell_`,
  `_lazySelfForSub`로 시작하는 컨테이너 멤버 이름을
  `container.reserved-name-prefix`로 거부했습니다. 5.0의 canonical generated
  prefix는 `_storage_`, `_override_`, `_innoDI`, `_InnoDI`이므로 앞의 네 예시는
  더 넓은 prefix 규칙으로 계속 예약됩니다. 그 namespace 밖의 예전 로컬
  spelling인 `_subBuildCell_`, `_lazyCell_`, `_lazySelfForSub`, `_resolved_`,
  `_task_`는 다시 사용할 수 있습니다.

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
