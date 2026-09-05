# InnoDI

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

컴파일 타임과 빌드 타임 검증, dependency graph 도구, hierarchy 검증,
SwiftUI helper를 함께 제공하는 Swift용 매크로 기반 DI 프레임워크입니다.

## 최소 예제

<!-- innodi:compile -->
```swift
import InnoDI

struct APIClient { let baseURL: String }

@DIContainer
struct AppContainer {
    @Input var baseURL: String
    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
    var apiClient: APIClient
}

let client = AppContainer(baseURL: "https://api.example.com").apiClient
```

사용되지 않을 수 있는 무거운 shared 서비스는 첫 접근 시 생성하도록 명시할
수 있습니다. 컨테이너 값 복사본은 하나의 논리 cache를 공유하고 별도로 만든
컨테이너는 서로 격리됩니다.

```swift
@Provide(.shared, initialization: .onDemand, factory: MetricsClient())
var metrics: MetricsClient
```

생성되는 `prewarm` 메서드는 선택한 on-demand provider만 준비하며 `Lazy`와
`Provider` 의존성은 계속 지연합니다. 비동기 소유 작업에는 `DIAsyncScope`를
사용해 개별 waiter 취소와 owner 종료를 분리하고, `DIAsyncPreparationPlan`으로
실패와 downstream 차단 상태를 구조적으로 확인할 수 있습니다.

## 왜 InnoDI인가

InnoDI는 DI wiring을 명시적이고 리뷰 가능한 상태로 유지하면서, 실패를 더
이른 단계에서 발견하고 싶은 팀을 위한 도구입니다.

- `@DIContainer`와 `@Provide`가 지원되는 유효한 non-generic Swift struct에서 컨테이너 API를 생성합니다.
- 매크로 검증이 로컬 실수를 확장 시점에 잡습니다.
- build validation과 graph CLI가 cross-file, cross-module, global graph 문제를 잡습니다.
- `InnoDISwiftUI`가 루트 경계의 반복적인 environment wiring을 줄여줍니다.
- `InnoDITesting`이 테스트·프리뷰 target에 동시성 안전 mock 저장소,
  interaction 검증, typed override preset을 선택적으로 제공합니다.

InnoDI는 runtime state machine이 아닙니다. 런타임 상태는 앱 레이어나
`InnoFlow`, `InnoRouter`, `InnoNetwork` 같은 companion framework에 두는
것을 전제로 합니다.
InnoDI는 의도적으로 `@Injected` property wrapper나 dynamic registration API를
제공하지 않습니다. 대신 명시적인 generated initializer, 리뷰 가능한 wiring,
더 이른 검증을 선택합니다.

## 언제 InnoDI를 선택할까

dependency wiring이 코드 리뷰에서 보이고, runtime 이전에 검증되며, graph
artifact로 점검 가능해야 한다면 InnoDI가 잘 맞습니다.

| 우선순위 | 추천 | 이유 |
| --- | --- | --- |
| 앱 dependency graph의 compile/build-time 검증 | InnoDI, [SafeDI](https://github.com/dfed/SafeDI), [Needle](https://github.com/uber/needle) | InnoDI는 macro-expanded Swift 표면, local macro diagnostic, build-support check, DAG CLI를 함께 제공합니다. |
| runtime registration, late binding, plugin-style composition | [Swinject](https://github.com/Swinject/Swinject), [Factory](https://github.com/hmlongco/Factory) | runtime container는 동적 교체가 쉽습니다. InnoDI는 명시적 initializer와 early validation을 우선합니다. |
| SwiftUI preview와 scoped test override | [Factory](https://github.com/hmlongco/Factory), [swift-dependencies](https://github.com/pointfreeco/swift-dependencies), InnoDI | InnoDI는 검증된 app container 위에 override와 SwiftUI root helper를 얹고 싶을 때 적합합니다. |
| feature ownership hierarchy와 graph visibility | InnoDI, [Needle](https://github.com/uber/needle), [SafeDI](https://github.com/dfed/SafeDI) | `@SubContainer`와 graph CLI ownership edge로 parent-owned child container를 표현합니다. |
| 기존 앱의 최저 도입 비용 | [Factory](https://github.com/hmlongco/Factory), [swift-dependencies](https://github.com/pointfreeco/swift-dependencies), incremental InnoDI | InnoDI는 container 정의와 macro/build validation을 요구합니다. payoff는 wiring 가시성과 graph check가 필요한 시점에 커집니다. |

실무에서는 공존도 가능합니다. 검증된 application graph는 InnoDI에 두고,
feature 내부의 runtime 값은 `swift-dependencies`나 작은 factory로 처리할 수
있습니다.

권장 layering 패턴은 *생성*은 InnoDI, *호출 단위 일시 override*는
`swift-dependencies`로 분리하는 것입니다. composition root에서
`@Dependency(\.date)` 같은 `DependencyKey`를 해석한 뒤 그 값을 container의
`@Input` 슬롯으로 전달하고, 테스트는
`withDependencies { $0.date = .constant(...) } operation:`로 한 호출 트리만
교체합니다. container를 다시 만들 필요도, validated graph를 재검증할 필요도
없습니다. InnoDI의 container 레벨 `Overrides` 빌더는 가짜 `APIClient` 같은
앱 전체 swap에 그대로 두고, `swift-dependencies`는 한 operation 동안만 유효한
override가 필요할 때 꺼냅니다.

## 요구 사항

- Swift tools version `6.2` (CI 검증: Swift 6.2 및 6.3)
- 플랫폼:
  - iOS 17+
  - macOS 13+
  - watchOS 10+
  - tvOS 17+
  - visionOS 1+

### 빌드 타임 validator의 파일시스템 요구 사항

빌드 플러그인은 live DAG validation을 Swift Package Manager scratch
디렉터리 아래의 layered POSIX lock으로 직렬화합니다.

1. `open(O_CREAT | O_EXCL | O_RDWR)`가 단일 lock file을 만듭니다.
2. `flock(LOCK_EX | LOCK_NB)`가 descriptor에 advisory exclusive lock을 더합니다.

InnoDI는 lock directory의 파일시스템을 자동 감지합니다. APFS, HFS+, ext4,
btrfs, xfs, tmpfs 같은 로컬 파일시스템은 지원합니다. NFS mount, SMB/CIFS,
WebDAV, FUSE 계열 파일시스템은 lock atomicity가 신뢰할 수 없을 때 shared
validation cache가 손상될 수 있으므로 기본적으로 거부합니다.

빌드 시스템이 derived data를 shared volume에 둬야 한다면, SPM의
`--scratch-path` 또는 Xcode derived-data 위치를 로컬 디렉터리로 지정하세요.

```sh
swift build --scratch-path /tmp/innodi-cache
```

운영자는 `INNODI_ALLOW_UNSAFE_LOCK=1`로 unsafe-filesystem fail-fast를
우회할 수 있지만, InnoDI는 감사 가능한 경고를 남기며 위험은 해당 build
environment에 남습니다. 자세한 진단과 복구 절차, 전체 파일시스템 표는
[Lock Safety](Sources/InnoDI/InnoDI.docc/lock-safety.md)를 참고하세요.

빌드 시점 검증기는 빠른 반복 또는 제약된 환경을 위한 두 개의 opt-out escape
hatch 를 제공합니다. `@DIContainer(validateDAG: false)` 는 컨테이너 단위로,
`INNODI_DISABLE_BUILD_VALIDATION=1` 은 빌드 플러그인 전체를 단락시킵니다. 모든
PR 은 `Tools/report-validate-dag-escape-hatches.sh` 를 실행해 이러한 escape
hatch 사용처를 워크플로 step summary 에 노출시키므로, 별도 CI 게이트 없이도
escape hatch 누적이 가시화됩니다. 프로덕션 CI 는 두 옵션 모두 unset 으로 유지
해야 합니다.

## 개인정보 보호

InnoDI는 두 런타임 제품 `InnoDI`와 `InnoDISwiftUI`에 Apple Privacy Manifest
(`PrivacyInfo.xcprivacy`)를 동봉합니다. 매니페스트는 사용자 추적 없음, 추적
도메인 없음, 수집 데이터 유형 없음, Required Reason API 사용 없음을 선언합니다.
빌드 시점 도구(InnoDIBuildSupport, dependency-graph CLI, 매크로 플러그인)는
사용자 앱에 임베드되지 않으므로 매니페스트에 영향을 주지 않습니다. iOS, watchOS,
tvOS, visionOS 앱에 InnoDI를 임베드하면 SwiftPM이 매니페스트를 자동으로
번들링하고 앱의 집계 개인정보 보고서에 표시됩니다.

## 설치

`Package.swift`에 InnoDI를 추가합니다.

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "5.1.0")
]
```

그 다음 필요한 product를 타깃에 연결합니다.

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI"
    ]
)
```

SwiftUI helper가 필요할 때만 `InnoDISwiftUI`를 함께 추가합니다.

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI",
        "InnoDISwiftUI"
    ]
)
```

생성된 `Sendable` mock, 재사용 override preset, strict interaction 검증이 필요한
테스트 또는 프리뷰 지원 target에만 `InnoDITesting`을 추가하세요. 이 product는
`InnoDI`에만 의존하며 Swift Testing이나 SwiftSyntax에는 의존하지 않습니다.

InnoDI 컨테이너 또는 standalone `@DIEnvironmentBridge`를 선언하는 모든 target에
build-time validation plugin을 연결합니다. 이는 선택적인 graph 시각화 단계가
아니라 5.0 정확성 계약의 필수 구성입니다. target-scoped full-source pass는
attached macro가 단독으로 확인할 수 없는 sibling extension의 custom initializer,
enclosing 또는 같은 target의 generated qualifier shadow, 현재 target에서 보이는
imported dependency target의 `public` 또는 `package` qualifier shadow, bridge의
direct-extension attachment와 standalone local target을 compile 전에 차단합니다.

Generated site가 class이거나 class 안에 중첩되면 superclass가 올 수 있는 첫
inherited type이 source-visible declaration과 typealias를 통해 해소되어야 합니다.
SDK 또는 binary에만 있거나, 해소되지 않거나, 모호한 첫 inherited type은
`generated-qualifier.inheritance-unverifiable`로 fail closed합니다. Generated
site를 struct/enum 또는 source-visible adapter로 옮기거나 target-scoped source
snapshot이 superclass chain을 볼 수 있게 하세요. 이 preflight는 Swift
type checker를 대신하는 semantic index가 아니라 보수적인 syntactic index입니다.

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI"
    ],
    plugins: [
        .plugin(name: "InnoDIDAGValidationPlugin", package: "InnoDI")
    ]
)
```

5.1부터 같은 product가 네이티브 Xcode build-tool plugin API도 지원합니다.
네이티브 Xcode project와 Tuist가 생성한 project는 package plugin을 각 container
target에 직접 연결할 수 있습니다. Tuist workspace에서는 plugin이 workspace root를
찾아 모든 production Swift source를 검증하므로 교차 project container 참조도 source
DAG에 포함됩니다.

Xcode plugin API는 Tuist의 전체 교차 project target dependency topology를 제공하지
않습니다. 따라서 5.1 fallback은 full-source DAG와 declaration 검증을 보존하지만
Xcode만으로 모든 module-edge hierarchy 규칙을 증명할 수는 없습니다.
component/root `@DIContainerRole` module 관계가 release gate라면 topology-aware
SwiftPM 또는 CI hierarchy 검증을 유지하세요. multi-destination variant가 같은 plugin
work directory를 공유하므로 Xcode 검증은 output file을 선언하지 않으며, 그 결과
Xcode가 매 build마다 validation command를 실행한다고 표시할 수 있습니다.

## 빠른 시작

<!-- innodi:compile -->
```swift
import Foundation
import InnoDI

protocol APIClientProtocol {
    func fetch() async throws -> Data
}

struct APIClient: APIClientProtocol {
    let baseURL: String
    func fetch() async throws -> Data { Data() }
}

@DIContainer
struct AppContainer {
    @Input
    var baseURL: String

    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
    var apiClient: any APIClientProtocol
}

let container = AppContainer(baseURL: "https://api.example.com")
_ = container.apiClient
```

이름이나 생성 로직이 `Type.self` + `with:`와 맞지 않으면 factory closure를
사용합니다.

```swift
@Provide(.shared, factory: { (baseURL: String) in
    APIClient(baseURL: baseURL)
})
var apiClient: any APIClientProtocol
```

## 먼저 읽을 문서

아래 순서로 읽는 것을 권장합니다.

1. [Overview](Sources/InnoDI/InnoDI.docc/ko.lproj/Overview.md)
2. [Validation](Sources/InnoDI/InnoDI.docc/ko.lproj/Validation.md)
3. [Policy Boundaries](Sources/InnoDI/InnoDI.docc/ko.lproj/PolicyBoundaries.md)
4. [Anti-Patterns](Sources/InnoDI/InnoDI.docc/ko.lproj/AntiPatterns.md)
5. [Module-Wide Init Detection](Sources/InnoDI/InnoDI.docc/ko.lproj/ModuleWideInitDetection.md)
6. [RELEASING.md](RELEASING.md)
7. [ROADMAP.md](ROADMAP.md)

## 핵심 API

### `@DIContainer`

`@DIContainer`는 다음을 합성합니다.

1. 필수 `@Input` 파라미터와 `.shared`, `.transient`, `@SubContainer`
   멤버용 optional override를 받는 primary `init(...)`
2. nested `Overrides` 타입
3. `init(<inputs...>, _ applyOverrides: (inout Overrides) -> Void)` 형태의 convenience init
4. `sync`, `throws`, `async`, `async throws` 4종류의 `withOverrides` overload

관리 멤버가 하나도 없는 경우까지 모든 컨테이너가 전체 overrides scaffolding을
생성합니다. 사용자가 nested `Overrides` 타입을 직접 선언하는 것은 InnoDI 6.0에서
지원하지 않으며 `container.overrides-name-conflict` 오류가 발생합니다. mount 가능한
override ABI는 매크로가 소유하도록 사용자 선언의 이름을 바꾸세요.

매크로는 부모 컨테이너의 mount 코드를 위해 compiler support 전용 별칭
`_InnoDIMountOverrides = Overrides`도 생성합니다. 이 underscore 이름을 직접
선언하거나 참조하지 마세요.

컨테이너의 모든 stored instance member에는 `@Provide` 또는 `@SubContainer`가
필요합니다. computed/static property는 계속 사용할 수 있습니다. 그래야 생성
initializer가 전체 상태를 소유하고 memberwise initializer 변화가 생기지 않습니다.

`@DIContainer`가 지원하는 선언은 file scope 또는 nominal type 안에 nested된,
유효하게 non-generic인 `struct`뿐입니다. 선언 자체와 모든 enclosing 선언에
generic parameter나 `where` clause가 없어야 합니다. `class`, `actor`, `enum`,
`protocol`, 직접 annotated된 `extension`, extension 안에 nested된 struct는
거부됩니다. 함수, closure, accessor, `switch` case를 포함한 executable/local
code scope 안의 선언도 거부됩니다. 이 경계는 `@DIContainerRole`에도 동일합니다.
runtime 또는 타입별 state는 protocol dependency나
`@Input` 뒤로 옮기세요.

명시적으로 `private`인 컨테이너도 sibling container가 생성된 mount surface에
접근할 수 없어 거부됩니다. 같은 파일에서 mount하려면 `fileprivate`를 사용하거나,
private namespace 안에 default-access container를 중첩하세요.

현재 Swift compiler는 computed-property body 안 타입의 attached macro를
확장할 때 accessor ancestry를 macro context에서 누락합니다. 이 edge case는
build-validation plugin과 dependency-graph CLI가 전체 source tree를 scan해
거부합니다. compiler-plugin macro 입력에서 빠지는 sibling extension도 이 단계가
검사합니다. 컨테이너를 선언하는 모든 target에 plugin을 연결하세요. full-source
preflight가 없으면 extension custom initializer가 정책을 우회할 수 있습니다.

```swift
@DIContainer(validateDAG: Bool = true)
@DIContainerRole(role: String, mainActor: Bool = false, validateDAG: Bool = true)
```

| 파라미터 | 기본값 | 의미 |
|---|---|---|
| `role` | `@DIContainerRole`에서 필수 | `ContainerRole.local`, `.component`, `.root` 중 하나입니다. Root role은 그래프 도달성 시작점을, component role은 모듈 간 마운트 계약을 정의합니다. |
| `validateDAG` | `true` | global DAG validation과 매크로의 local graph-derived 검증을 켭니다. `false`면 global DAG와 local cycle 검증은 건너뛰지만, 선언 검증과 명시적 sibling edge의 효과 호환성 검증은 계속 동작합니다. |
| `mainActor` | `false` | 의존성 accessor, 모든 생성 initializer, `Overrides`, convenience initializer·`withOverrides`·child override·component mount에 쓰이는 `applyOverrides` 함수 타입, 네 가지 `withOverrides` operation closure, feature-root helper에 `@MainActor` 격리를 적용합니다. `@DIContainerRole(role: ContainerRole.component)`와 함께 사용하면 생성된 `<Container>Dependencies` protocol과 `init(dependencies:_:)`도 격리되고, 전용 `_InnoDIMainActorComponentMountable` protocol에 conform합니다. 옵션을 사용하지 않는 일반 component는 `_InnoDIComponentMountable`을 계속 사용합니다. Actor 밖에서 사용하려면 명시적인 hop이 필요하며, UI 루트 컨테이너에 권장됩니다. |

6.0의 generic component mounting helper는 두 marker protocol을 구분해야
합니다. 일반 component에는 `_InnoDIComponentMountable`을 유지하고,
`mainActor: true` component에는 `_InnoDIMainActorComponentMountable` constraint와
`@MainActor` override closure를 쓰는 `@MainActor` overload를 추가하세요.

non-`Sendable` container/component 값은 `@MainActor` caller를 사용하거나
`MainActor.run` 안에서 생성하고 소비해 main actor에 유지하세요. direct `await`는
`withOverrides` operation result처럼 격리된 작업이 `Sendable` 결과를 반환할 때
적합하며, container 자체를 actor 밖으로 옮겨도 안전하게 만들지는 않습니다.

`@DIContainer`는 annotated type이나 매칭되는 extension에 사용자 정의 `init`
선언을 허용하지 않습니다. 생성된 initializer를 사용하거나, 매크로 없이
수동으로 wiring해야 합니다. annotation body의 initializer는 macro가 진단하고,
같은 파일과 다른 파일 extension의 initializer는 필수 build plugin이 compile 전에
진단합니다.

### `@Provide`와 스코프

InnoDI 6.0에서 `@Provide`는 `@DIContainer`가 붙은 동일한 지원 struct의 직접적이고
평범한 stored instance `var`에만 붙일 수 있습니다. `let`, computed/observed
property, `lazy`, `weak`, `unowned`, `static`/`class`, standalone, 간접 nested
사용은 거부됩니다. 생성되는 provider accessor는 InnoDI가 소유하므로
`_InnoDIProvideAccessor`를 직접 붙이면 안 됩니다.

Provider 선언의 attribute와 access control도 닫힌 계약을 따릅니다. Property
wrapper, conditional 또는 unknown attribute, `private(set)` 같은 setter access
modifier, custom global-actor attribute는 거부됩니다. `@Provide` 외에 source에
직접 쓰는 property-level attribute는 허용되지 않으며 `@MainActor`도 포함됩니다.
Actor 격리는 `@DIContainerRole(role: ContainerRole.local, mainActor: true)`로 요청하세요. Provider 선언과
accessor에 InnoDI가 생성한 격리 attribute는 내부 compiler support입니다. 완전한
`@Provide` 멤버 선언을 `#if` 안에 두는 형태도
`provide.conditional-declaration-unsupported` 진단으로 거부됩니다.
선언은 조건문 밖에 두고 factory 또는 주입 구현 안에서 분기하세요.
프로퍼티마다 `@Provide`는 정확히 하나만 붙일 수 있으며, 중복 attribute는
`provide.duplicate-attribute`로 거부됩니다. 직접 선언한 provider property와
root factory closure의 dependency parameter는 각각 고유한 effective 이름을
가져야 하며, 중복 identity는 generated lookup이나 storage code를 만들기 전에
거부됩니다. 두 선언은 escaped identifier를 사용할 수 없으며 5.0에서는
backtick으로 감싼 property와 factory parameter 이름을 거부합니다.
`@SubContainer` property 이름도 generated child storage, override, root helper
identity의 입력이므로 escaped identifier를 사용할 수 없습니다. Generated
storage/support declaration은 `_storage_`, `_override_`, `_innoDI`, `_InnoDI`를
예약하며 direct declaration의 정확한 이름 `InnoDI`도 예약합니다. `Swift`,
`_Concurrency`와 SwiftUI bridge anchor는 attached macro가 볼 수 있는 type
namespace에서 예약합니다. 정확한
5.0 matrix는 [Migration Guide](Sources/InnoDI/InnoDI.docc/ko.lproj/MigrationGuide.md)를
참고하세요. target-scoped full-source pass는 SwiftSyntax가 attached macro에서 숨기는
enclosing declaration의 같은 이름 멤버, 같은 target의 qualifier shadow, 현재 target에서
보이는 imported dependency target의 `public` 또는 `package` qualifier shadow를
거부합니다. Class bridge 또는 이를 감싸는 class에서는 source-visible superclass
chain도 따라갑니다. 상속된 type member `Swift`와 `SwiftUI`는 거부하지만 상속된
`InnoDISwiftUI`는 안전합니다. 직접 또는 lexical scope에서 보이는
`InnoDISwiftUI` declaration은 계속 예약됩니다. 이 검사는 보수적인 syntactic
index이므로 SDK·binary에만 있거나 해소되지 않거나 모호한 첫 inherited type은
superclass에 shadow가 없다고 추측하지 않고
`generated-qualifier.inheritance-unverifiable`로 fail closed합니다. 명시적 property type에는 opaque
`some Protocol`이나 implicitly unwrapped optional `T!`를 사용할 수 없습니다.
각각 `any Protocol`, 명시적인 `T` 또는 `T?`로 바꾸세요. Compiler-support
accessor와 다른 property wrapper를 의도적으로 위조해 함께 붙이면 InnoDI의
misuse 진단과 함께 Swift 자체의 구조 진단도 발생할 수 있습니다.

쓰기 전에 machine-readable migration inventory를 만들려면
`swift run InnoDI-Migrate --root . --report --output migration-report.json`을
실행하세요. Schema-v1 리포트에는 경로와 진단만 포함되고 source 본문은 포함되지
않으며, exit code는 `0`(clean), `1`(변경 필요), `2`(차단)입니다.

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    initialization: DIInitialization = .eager,
    factory: Any? = nil,
    asyncFactory: Any? = nil
)
```

| 스코프 | 의미 | 생성 규칙 |
|---|---|---|
| `@Input` | 컨테이너 생성 시 외부에서 주입하는 의존성 | `factory:`, `asyncFactory:`, `Type.self`, property initializer, `with:`를 모두 선언하지 않음 |
| `.shared` | 컨테이너 인스턴스당 1회 생성 후 재사용 | `factory:`, `asyncFactory:`, `Type.self`, property initializer 중 정확히 하나 선언 |
| `.transient` | 접근할 때마다 새로 생성 | `factory:`, `asyncFactory:`, `Type.self`, property initializer 중 정확히 하나 선언 |

추가 규칙:

- `.shared`와 `.transient`에서 `factory:`, `asyncFactory:`, `Type.self`, property
  initializer 네 생성 source는 서로 배타적입니다.
- `@Input`은 모든 생성 source와 `with:`를 거부합니다.
- 생성되는 `@Input` initializer 파라미터는 선언 타입 `T`의 eager 값입니다. Swift는
  평소와 같이 initializer 호출 전에 `try` / `await` 인자 식을 평가합니다. 직접
  표기한 non-optional function type은 자동 감지해 escaping 파라미터로 생성합니다.
  Non-optional function type이 typealias 뒤에 숨었다면
  `@Input(escaping: true)`를 사용하세요. `escaping:`은 literal Bool이고
  `@Input`에서만 유효합니다. 명백한 nonfunction/optional-function 형태는 거부되며,
  보수적으로 허용된 identifier/member alias가 실제 non-optional function으로
  해석되지 않으면 Swift 자체 진단이 발생할 수 있습니다.
- `asyncFactory`는 `.shared`와 `.transient`에서 지원되며 반드시 `async`
  클로저여야 합니다.
- `with:`는 `Type.self` 생성 형태에서만 허용됩니다. Literal 배열의 각 항목은
  `with: [\Self.config]`처럼 정확히 canonical direct-member 표기인
  `\Self.member`여야 하며 `with: []`도 허용됩니다. 이름이 있는 container,
  module-qualified, typealias root는 물론 nested component, optional chaining,
  subscript, 계산된 배열 원소도 거부됩니다. 참조되는 provider는 모두 동기 생성
  방식이어야 합니다.
- 선언된 property type이 storage shape을 결정합니다. Concrete nominal type은
  concrete storage를, `any Protocol`은 existential storage를 사용합니다.
- factory 파라미터와 `with:` wiring의 이름 해석은 멤버 이름 기준으로 엄격하게 이뤄집니다.

Sibling DI edge는 다음처럼 닫힌 문법에서만 만들어집니다.

- root `factory:` 또는 `asyncFactory:` 클로저 리터럴의 이름 있는 파라미터마다
  edge 하나를 만듭니다. Nested 클로저나 임의 identifier는 edge를 추가하지 않습니다.
- `Type.self` 생성은 literal canonical `\Self.member` key-path 배열에서 edge를
  만들며 동기 provider만 target으로 삼을 수 있습니다.
- 클로저가 아닌 `factory:` 표현식과 property initializer는 opaque한 zero-edge
  생성 source입니다. 여기서는 sibling container member를 참조하면 안 됩니다.
  DI wiring은 root 클로저 파라미터로 바꾸고, DI edge가 필요 없다면 qualified
  global/static 생성 symbol을 사용하세요.

Factory 효과는 명시적으로 선언하며 의존성에서 추론하지 않습니다. 비동기
consumer에는 `asyncFactory:`를 사용하고, throwing 비동기 provider를 소비한다면
클로저에 `async throws`를 명시하세요. 효과 호환성은 `validateDAG: false`여도
모든 명시적 edge에서 검증됩니다.

| Provider | sync consumer | `async` consumer | `async throws` consumer |
|---|---:|---:|---:|
| sync | 허용 | 허용 | 허용 |
| `async` | 거부 | 허용 | 허용 |
| `async throws` | 거부 | 거부 | 허용 |

`Lazy<T>`와 `Provider<T>`는 동기 deferred wrapper입니다. Async target은
거부됩니다.

## 검증 모델

InnoDI는 여러 단계에서 컨테이너를 검증합니다.

1. Macro validation
   - 로컬 스코프 규칙
   - missing factory
   - declaration-order check
   - local cycle
   - invalid `init` declaration
2. Build validation
   - cross-file `init` conflict
   - semantic reference check
   - hierarchy validation
   - artifact generation
3. Global DAG validation
   - `swift run InnoDI-DependencyGraph --root . --validate-dag`

`validateDAG: false`는 의도적으로 좁은 opt-out입니다. global DAG validation과
local cycle 같은 graph-derived 검증만 건너뜁니다. 선언 검증과 root 클로저 또는
`with:`가 만든 명시적 sibling edge의 효과 호환성 검증은 꺼지지 않습니다.

## Overrides 빌더

생성되는 `Overrides` 빌더를 쓰면 테스트에서 필요한 멤버만 바꿀 수 있습니다.

```swift
let container = AppContainer(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
}
```

한 번의 operation에만 override를 묶고 싶으면:

```swift
let result = try await AppContainer.withOverrides(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
} operation: { container in
    try await container.apiClient.fetch()
}
```

중요한 점:

- input-only container도 비어 있는 builder를 합성합니다.
- child container가 input-only여도 `<name>Overrides` 클로저는 컴파일되며,
  child에 override 가능한 멤버가 생기기 전까지는 no-op으로 동작합니다.
- 컨테이너는 nested `Overrides` 타입을 직접 선언하면 안 됩니다. InnoDI 6.0은
  부분적이고 mount 불가능한 API를 생성하는 대신 이 충돌을 오류로 거부합니다.

## `Lazy<T>`와 `Provider<T>`

사이클 검출에서 제외되는 지연 참조가 필요하면 `Lazy<T>`를 사용합니다.

`.transient` 의존성을 호출할 때마다 다시 진입해야 하면 `Provider<T>`를
사용합니다.

```swift
@Provide(.shared, factory: { (service: Lazy<Service>) in
    Consumer(service: service)
})
var consumer: Consumer
```

```swift
@Provide(.shared, factory: { (requests: Provider<Request>) in
    RequestLogger(requests: requests)
})
var logger: RequestLogger
```

두 wrapper 모두 의도적으로 non-`Sendable`이며, 컨테이너가 가진 원래 격리
도메인 안에 머물러야 합니다. 또한 둘 다 동기 wrapper이므로
`asyncFactory` 멤버를 target으로 삼을 수 없습니다.

## Nested Container와 Hierarchy

`@SubContainer`는 parent가 소유하는 child container를 모델링합니다.

```swift
@SubContainer(scope: .shared, with: [\.config, \.apiClient])
var feature: FeatureContainer
```

핵심 규칙:

- `scope:`는 필수입니다.
- 지원되는 parent `@DIContainer` 안에서 `#if` 밖의 직접적이고 평범한 stored
  instance `var`에 `@SubContainer`를 정확히 하나만 선언합니다. Wrapper,
  storage/accessor modifier, unknown attribute, 그리고
  `InnoDI._InnoDISubContainerAccessor`의 수동 부착은 지원하지 않습니다.
- parent `@Provide` 후보가 0개 또는 1개일 때만 이름 기준 implicit wiring을 편의로 허용합니다.
- parent 후보가 여러 개면 `with:` 또는 `bindings:`로 명시 wiring해야 합니다.
- `with:`는 같은 이름 subset/order를 forward합니다.
- `bindings:`는 child input label과 parent member 이름이 다를 때 remap합니다.
- `featureRoot:` / `featureRoots:`는 같은 property에 별도 peer macro를 쌓지
  않고 parent에 SwiftUI root helper를 생성합니다.
- `with:` 또는 `bindings:` 중 정확히 하나의 wiring form만 사용합니다.
- parent의 `Overrides`에는 전체 교체 슬롯(`feature`)과 child override closure(`featureOverrides`)가 모두 추가됩니다.

cross-module ownership에는 다음을 사용합니다.

- mount 가능한 child container용 `@DIContainerRole(role: ContainerRole.component)`
- rooted workspace-level validation용 `@DIContainerRole(role: ContainerRole.root)`

## SwiftUI Helper

`InnoDISwiftUI`는 컨테이너 계약 위에 작은 SwiftUI 통합 레이어를 더합니다.

- `.innodi(container)`는 생성된 environment bridge를 view tree에 적용합니다.
- `@DIEnvironmentBridge`는 container member를 SwiftUI environment key에 매핑합니다.
- `@SubContainer(..., featureRoot:)`와 `featureRoots:`는 child container의
  default 또는 named feature-root helper를 생성합니다.
- `DIContainerHost`는 fixed/assisted child를 route, document, window identity별로
  지연 생성해 소유합니다. 앱이 loading/failure/retry UI를 구성하고,
  `onDisappear` 대신 실제 close 경로에서 lifecycle handle을 호출합니다.
- InnoDI 5.0에서는 deprecated compatibility macro인 `@DIFeatureRoot`를
  제거합니다. 한 property에 peer macro를 겹치지 않도록 `@SubContainer`의
  `featureRoot:` 또는 `featureRoots:` argument로 교체하세요.

로컬 UI 루트의 생성 API를 main actor에 격리하려면
`@DIContainerRole(role: ContainerRole.local, mainActor: true)`를 사용하세요.
component role에 `mainActor: true`를 지정하면
`<Container>Dependencies` protocol, `init(dependencies:_:)`, override 적용 closure
타입도 격리되고 전용 `_InnoDIMainActorComponentMountable` protocol에 conform합니다.
일반 component는 `_InnoDIComponentMountable`을 계속 사용합니다. non-`Sendable`
값의 생성과 사용은 main actor 안에 유지하고, direct `await`는 격리된 작업이
`Sendable` 결과를 반환할 때만 사용하세요.

## CLI와 릴리즈 표면

그래프 렌더링:

```bash
swift run InnoDI-DependencyGraph --root . --root-pruning all
```

global DAG 검증:

```bash
swift run InnoDI-DependencyGraph --root . --validate-dag
```

그래프 포함 경로와 역방향 영향 범위를 확인하고 명시적 루트에서 도달하지
못하는 컨테이너 찾기:

```bash
swift run InnoDI-DependencyGraph --root . --why FeatureContainer
swift run InnoDI-DependencyGraph --root . --dependents NetworkContainer
swift run InnoDI-DependencyGraph --root . --unused
```

target-scoped JSON 그래프 artifact 두 개 비교:

```bash
swift run InnoDI-DependencyGraph --diff before.json after.json
swift run InnoDI-DependencyGraph --diff before.json after.json --check-contract
```

`--check-contract`는 scope, container, provider, edge 계약이 하나라도 바뀌면
종료 코드 5를 반환하므로 CI에서 검토된 그래프 스냅샷 갱신만 허용할 수
있습니다. schema v4 provider 레코드는 타입, lifetime, 초기화 정책, 격리,
effect를 포함하며 source 줄/열 이동만으로는 계약 변경이 되지 않습니다.
이전 graph schema는 unchanged로 취급하지 않고 명시적으로 거부합니다.

`--why App.AppContainer.client`처럼 provider selector도 `--why`와
`--dependents`에서 사용할 수 있습니다. 결과는 provider 계약과 source 위치를
포함합니다. runtime cache/override/async provenance는 opt-in `DITraceContext`와
`DIBoundedTraceBuffer`로 수집하며, 비활성 경로에서는 ID, event, buffer를 만들지
않고 입력값이나 오류 payload도 기록하지 않습니다. graph query가 출력한 stable
provider ID를 `trace.withResolution(providerID: id) { ... }`에 전달하면 성공,
실패, 협조적 취소가 같은 runtime instance ID로 연결됩니다. cache hit와
override 지점은 `record`로 명시적 terminal event를 추가할 수 있습니다.

migration 또는 도입 전 read-only doctor를 실행합니다.

```bash
swift run InnoDI-Doctor --root .
swift run InnoDI-Doctor --root . --json
```

기본 모드는 resolve, build, write, cache 삭제, process 종료를 하지 않습니다.
`--apply`는 migrator의 atomic safety 검사를 명시적으로 사용하고 `--verify`는
별도로 `swift build`를 허용합니다. report는 제안/적용 경로, 두 번째 실행의
idempotency, 검증 상태를 구분합니다.

## Collection 조합

`@Multibinding([])`은 명시적 empty collection입니다. nonempty array는 생성된
Swift array를 compiler assignability witness로 사용하므로 문자열 타입 추정
없이 concrete 구현을 existential element로 합성할 수 있습니다.
`DICollectionGroup`과 `DIKeyedCollection`은 명시적으로 export한 module 출력을
호출자 순서로 합치고 keyed collision을 거부합니다. `DIProviderCollection`과
`DIKeyedProviderCollection`은 선택한 index 또는 key만 resolve합니다.

consumer target에서 매크로가 생성한 Swift 코드 확인:

```bash
Tools/dump-macro-expansions.sh \
  --package-path /path/to/ConsumerPackage \
  --target App
```

InnoDI checkout에서 스크립트를 실행하고 `--package-path`로 consumer를
지정하세요. 별도 scratch build를 사용해 전체 결과를 기본적으로 consumer의
`.build/innodi/macro-expansions.swift`에 기록하며, 생성 조각이 `Sources/`나
`Tests/`에 들어가는 것은 차단합니다. consumer의 일반 build cache는 건드리지
않습니다. 선언 하나만 볼 때는 Xcode의 **Expand Macro**가 가장 빠르고, 이
명령은 target 전체를 리뷰 가능한 artifact로 남길 때 사용합니다.

DocC 생성:

```bash
Tools/generate-docc.sh
```

릴리즈 노트와 업그레이드 노트는 [RELEASING.md](RELEASING.md)에 모여 있습니다.

## 예제

- [Examples/README.md](Examples/README.md)
- [Examples/SwiftUIExample](Examples/SwiftUIExample)
- [Examples/PreviewInjectionExample](Examples/PreviewInjectionExample)
- [Sources/InnoDIExamples/main.swift](Sources/InnoDIExamples/main.swift)
