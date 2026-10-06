# InnoDI

[![Release](https://img.shields.io/github/v/release/InnoSquadCorp/InnoDI)](https://github.com/InnoSquadCorp/InnoDI/releases) [![License](https://img.shields.io/github/license/InnoSquadCorp/InnoDI)](LICENSE) [Swift Package Index](https://swiftpackageindex.com/InnoSquadCorp/InnoDI) · [CI and public operations](docs/automation-policy.md)

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

> 이 페이지는 **InnoDI 7.0.0** 문서입니다. 6.x에서 필요한 소스 변경은
> [마이그레이션 가이드](Sources/InnoDI/InnoDI.docc/ko.lproj/MigrationGuide.md#6x--70)를 따르세요.
> [버전 고정 7.0.0 문서](https://github.com/InnoSquadCorp/InnoDI/blob/7.0.0/README.ko.md).

컴파일 타임과 빌드 타임 검증, dependency graph 도구, hierarchy 검증,
SwiftUI helper를 함께 제공하는 Swift용 매크로 기반 DI 프레임워크입니다.

## 최소 예제

먼저 [설치](#설치) 단계에 따라 package를 추가하고 validation plugin을
연결하세요. 아래 예제는 같은 서비스를 테스트용 값으로 교체하는 과정까지 보여줍니다.

target의 기본 격리가 MainActor라면 컨테이너에 `@MainActor` 또는 `nonisolated`를
명시하세요. 매크로는 이 빌드 설정을 추론할 수 없습니다.
[격리 경계 안내](Sources/InnoDI/InnoDI.docc/ko.lproj/DIContainer.md#기본-격리가-mainactor인-타깃)를 참고하세요.

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

let live = AppContainer(baseURL: "https://api.example.com")
let test = AppContainer(baseURL: "https://api.example.com") {
    $0.apiClient = APIClient(baseURL: "https://test.example.com")
}
precondition(live.apiClient.baseURL == "https://api.example.com")
precondition(test.apiClient.baseURL == "https://test.example.com")
```

사용되지 않을 수 있는 무거운 shared 서비스는 첫 접근 시 생성하도록 명시할
수 있습니다. 컨테이너 값 복사본은 하나의 논리 cache를 공유하고 별도로 만든
컨테이너는 서로 격리됩니다.

```swift
@Provide(.shared, initialization: .onDemand, factory: MetricsClient())
var metrics: MetricsClient
```

생성되는 `prewarm` 메서드는 선택한 on-demand provider만 준비하며 `Lazy`와
`Provider` 의존성은 계속 지연합니다. 같은 `initialization: .onDemand` 옵션을
`asyncFactory:`에도 쓸 수 있으며, 이때 컨테이너에 `closeAsyncProviders()`가
생성됩니다. 준비, 재시도, 명시적인 종료가 필요한 비동기 작업은
[`generateOwned: true`와 owned container](Sources/InnoDI/InnoDI.docc/ko.lproj/OwnedContainers.md)에서
시작하세요. `makeOwned`는 준비 완료를 뜻하지 않습니다. report를 반환하는
`prepare`를 쓸 때는 `report.isReady`를 확인한 뒤 서비스를 사용하세요.

## 왜 InnoDI인가

InnoDI는 DI wiring을 명시적이고 리뷰 가능한 상태로 유지하면서, 실패를 더
이른 단계에서 발견하고 싶은 팀을 위한 도구입니다.

- `@DIContainer`와 `@Provide`가 지원되는 유효한 non-generic Swift struct에서 컨테이너 API를 생성합니다.
- 매크로 검증이 로컬 실수를 확장 시점에 잡습니다.
- build validation과 graph CLI가 cross-file, cross-module, global graph 문제를 잡습니다.
- `InnoDISwiftUI`가 루트 경계의 반복적인 environment wiring을 줄여줍니다.
- `InnoDITesting`이 테스트·프리뷰 target에 동시성 안전 mock 저장소,
  generation 기반 reset, interaction 검증, typed override preset을 선택적으로
  제공합니다.

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

기존 앱을 옮긴다면
[Factory에서 옮기기](Sources/InnoDI/InnoDI.docc/ko.lproj/MigratingFromFactory.md)나
[Swinject에서 옮기기](Sources/InnoDI/InnoDI.docc/ko.lproj/MigratingFromSwinject.md)의
개념 대응표, 옮기는 순서, 컴파일되는 예제를 참고하세요.

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

- Swift tools version `6.2` (CI 검증: Swift 6.2 / 6.3 / 6.4. 매크로 빌드는 Xcode 27 / Swift 6.4에서 SwiftSyntax prebuilt를 씁니다)
- 플랫폼:
  - iOS 17+
  - macOS 14+
  - watchOS 10+
  - tvOS 17+
  - visionOS 1+

InnoDI는 Apple 플랫폼만 지원합니다. CI는 Linux를 빌드하거나 테스트하지 않으며,
`InnoDITesting`은 Apple `os` 모듈을 조건 없이 import합니다.

InnoDI 7.0.0은 `swift-syntax`를 `604.0.0`으로 고정합니다.
`509.0.0..<604.0.0`을 요구하는
[Mockable 0.6.4](https://github.com/Kolos65/Mockable/blob/0.6.4/Package.swift)와는
같은 SwiftPM graph에서 해석할 수 없습니다. 업그레이드 전에 소비자 전체의
의존성을 확인하세요. lockfile 변경이나 버전 범위 완화만으로 매크로 호환성이
보장되지는 않으며, 의존성 해석과 실제 매크로 사용을 모두 검증해야 합니다.

빌드 시점 validator는 lock과 cache를 SwiftPM scratch 디렉터리 아래에 두며, 이
디렉터리는 APFS 같은 로컬 파일시스템에 있어야 합니다. NFS, SMB, WebDAV, FUSE
mount는 기본적으로 거부합니다. 파일시스템 표와 복구 절차는
[Lock Safety](Sources/InnoDI/InnoDI.docc/lock-safety.md)를 참고하세요.

## 개인정보 보호

InnoDI는 두 런타임 제품 `InnoDI`와 `InnoDISwiftUI`에 Apple Privacy Manifest
(`PrivacyInfo.xcprivacy`)를 동봉합니다. 매니페스트는 사용자 추적 없음, 추적
도메인 없음, 수집 데이터 유형 없음, Required Reason API 사용 없음을 선언합니다.
빌드 시점 도구(InnoDIBuildSupport, dependency-graph CLI, 매크로 플러그인)는
사용자 앱에 임베드되지 않으므로 매니페스트에 영향을 주지 않습니다. iOS, watchOS,
tvOS, visionOS 앱에 InnoDI를 임베드하면 SwiftPM이 매니페스트를 자동으로
번들링하고 앱의 집계 개인정보 보고서에 표시됩니다.

## 설치

설치는 세 단계입니다. 패키지를 추가하고, 검증 플러그인을 연결하고, 첫 컨테이너를
작성합니다.

### 1. 패키지 추가

`Package.swift`에 InnoDI를 추가합니다.

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "7.0.0")
]
```

이하 product·plugin·API 예제는 모두 **InnoDI 7.0.0**을 기준으로 합니다.
6.x에서 필요한 소스 변경은
[마이그레이션 가이드](Sources/InnoDI/InnoDI.docc/ko.lproj/MigrationGuide.md#6x--70)를 따르세요.

그 다음 필요한 product를 연결합니다. `InnoDI`가 핵심입니다. SwiftUI helper가
필요하면 `InnoDISwiftUI`를 추가하고, `InnoDITesting`은 생성 mock이나 override
preset을 쓰는 테스트 또는 프리뷰 지원 target에만 추가하세요.
[Auto Mock](Sources/InnoDI/InnoDI.docc/AutoMock.md)을 참고하세요.

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI"
    ]
)
```

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI",
        "InnoDISwiftUI"
    ]
)
```

### 2. 검증 플러그인 연결

InnoDI 컨테이너 또는 standalone `@DIEnvironmentBridge`를 선언하는 모든 target에
`InnoDIDAGValidationPlugin`을 연결합니다. 이 플러그인은 정확성 계약의
일부입니다. Swift가 target을 컴파일하기 전에, 다른 파일의 custom initializer,
qualifier shadow, 전역 의존성 그래프처럼 attached macro가 볼 수 없는 것을
검사합니다.

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

같은 플러그인이 native Xcode 프로젝트와 Tuist 프로젝트에서도 동작합니다.
[Integration Guide](Sources/InnoDI/InnoDI.docc/ko.lproj/IntegrationGuide.md#빌드-플러그인)는
Xcode와 Tuist의 한계, `generated-qualifier.inheritance-unverifiable` 뒤의
superclass 규칙, scratch path 요구 사항을 다룹니다.
[Plugin Opt-Out](Sources/InnoDI/InnoDI.docc/PluginOptOut.md)은 컨테이너 단위
`validateDAG: false`와 빌드 전체 `INNODI_DISABLE_BUILD_VALIDATION=1` escape
hatch를 설명하며, 프로덕션 CI는 두 옵션을 모두 설정하지 않아야 합니다.

### 3. 첫 컨테이너 작성

아래 빠른 시작으로 이어가세요.
[튜토리얼](Sources/InnoDI/InnoDI.docc/Tutorial-01-Hello.md)은 컨테이너를 단계별로
만듭니다.

## 빠른 시작

<!-- innodi:compile -->
```swift
import Foundation
import InnoDI

protocol APIClientProtocol {
    nonisolated(nonsending) func fetch() async throws -> Data
}

struct APIClient: APIClientProtocol {
    let baseURL: String
    nonisolated(nonsending) func fetch() async throws -> Data { Data() }
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

struct MockAPIClient: APIClientProtocol {
    nonisolated(nonsending) func fetch() async throws -> Data { Data([0x01]) }
}
let test = AppContainer(baseURL: "https://api.example.com") {
    $0.apiClient = MockAPIClient()
}
_ = test.apiClient

let result = try await AppContainer.withOverrides(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
} operation: { container in
    try await container.apiClient.fetch()
}
precondition(result == Data([0x01]))
```

비동기 프로토콜 메서드의 `nonisolated(nonsending)`은 호출자의 격리를 유지하므로
MainActor에서도 Sendable이 아닌 서비스를 이 작업에 사용할 수 있습니다.

이름이나 생성 로직이 `Type.self` + `with:`와 맞지 않으면 factory closure를
사용합니다.

```swift
@Provide(.shared, factory: { (baseURL: String) in
    APIClient(baseURL: baseURL)
})
var apiClient: any APIClientProtocol
```

## 먼저 읽을 문서

필요한 작업에서 시작하세요.

1. 동기 서비스와 값: [Overview](Sources/InnoDI/InnoDI.docc/ko.lproj/Overview.md)
2. 준비와 종료가 필요한 비동기 작업: [Owned Containers](Sources/InnoDI/InnoDI.docc/ko.lproj/OwnedContainers.md)
3. 테스트와 프리뷰: 위 Quick Start의 mock override와 [Auto Mock](Sources/InnoDI/InnoDI.docc/ko.lproj/AutoMock.md)

오류를 고칠 때는 [Validation](Sources/InnoDI/InnoDI.docc/ko.lproj/Validation.md)과
[Policy Boundaries](Sources/InnoDI/InnoDI.docc/ko.lproj/PolicyBoundaries.md)를,
업그레이드할 때는 [CHANGELOG.md](CHANGELOG.md)를 확인하세요.

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
@DIContainer(
    validateDAG: Bool = true,
    initializationOrder: String = ContainerInitializationOrder.declaration,
    generateOwned: Bool = false
)
@DIContainerRole(
    role: String,
    mainActor: Bool = false,
    validateDAG: Bool = true,
    initializationOrder: String = ContainerInitializationOrder.declaration,
    generateOwned: Bool = false
)
```

| 파라미터 | 기본값 | 의미 |
|---|---|---|
| `role` | `@DIContainerRole`에서 필수 | `ContainerRole.local`, `.component`, `.root` 중 하나입니다. Root role은 그래프 도달성 시작점을, component role은 모듈 간 마운트 계약을 정의합니다. |
| `validateDAG` | `true` | global DAG와 local graph-derived 검증을 켭니다. `false`여도 로컬 소유권 순환, 선언, 명시적 sibling edge의 효과 호환성 검사는 유지됩니다. |
| `mainActor` | `false` | 의존성 accessor, 모든 생성 initializer, `Overrides`, override callback, child/component/assisted-factory 전달, operation closure, feature-root helper에 `@MainActor` 격리를 적용합니다. 컨테이너에 직접 쓴 `@MainActor`도 같은 격리를 선택합니다. Component에서는 생성된 dependency protocol과 `init(dependencies:_:)`도 격리하고 `_InnoDIMainActorComponentMountable`을 사용합니다. Annotation과 옵션이 모두 없는 component는 `_InnoDIComponentMountable`을 사용합니다. UI 루트 컨테이너에 권장됩니다. |
| `initializationOrder` | `ContainerInitializationOrder.declaration` | full named token의 `.dependency`로 shared provider를 의존성 순서로 생성합니다. 도입 전에 factory 부수효과를 검토하세요. |
| `generateOwned` | `false` | `makeOwned(...)`와 준비·재시도·종료를 위한 별도 owned view를 생성합니다. 원래 컨테이너의 custom method와 conformance는 view에 옮겨지지 않습니다. |

## 의존성 순서 초기화 opt-in

기본값 `ContainerInitializationOrder.declaration`은 기존 생성 규칙을 유지합니다.
순환 없는 shared provider를 선언 위치와 관계없이 연결하려면
`ContainerInitializationOrder.dependency`를 명시합니다. 두 named token과
`InnoDI.`로 한정한 표현만 허용하며 문자열 literal, 변수, `.dependency` 축약은
지원하지 않습니다.

```swift
@DIContainer(initializationOrder: ContainerInitializationOrder.dependency)
struct AppContainer {
    @Provide(.shared, factory: { (configuration: Configuration) in
        Client(configuration: configuration)
    }) var client: Client
    @Provide(.shared, factory: Configuration()) var configuration: Configuration
}
```

매크로는 동기 shared 생성 단계를 먼저 수행하고, 그다음 비동기 shared handle을
생성합니다. 각 단계에서 hard dependency가 consumer보다 먼저 오며, 준비된
provider가 여러 개이면 원래 선언 위치가 빠른 것을 선택합니다. 이미 유효한
선언 순서의 생성 순서는 유지됩니다. 입력, initializer 인자 순서, override field와
child mount 방식은 바뀌지 않습니다.

이 옵션은 명시적인 동작 선택입니다. forward dependency는 factory 부수효과의
순서를 바꿀 수 있으므로 도입 시 초기화 trace를 검토하세요. factory의 순수성을
추측하지 않습니다. 비동기 완료 순서는 실행에 따라 달라지며 독립 task를 직렬화하지
않습니다. on-demand provider의 capture/cell 준비 순서만 바뀌고, 사용하지 않은
서비스를 미리 만들지는 않습니다.

`Lazy`와 `Provider`는 계속 지연되지만 ownership cycle 검사에는 포함됩니다.
`validateDAG: false`여도 순환은 거부합니다. 동기 factory의 async 의존성,
shared의 transient hard dependency, provider의 child-container 의존성을
새롭게 허용하지 않습니다. close, cancellation, retry와 container copy의 수명
계약도 바꾸지 않습니다.

기존 container는 migration이 필요하지 않습니다. 도입에는 인자 하나를 추가하며,
부수효과 검토 없이 선언을 자동 재배치하거나 앱 전체의 기본값을 바꾸지 마세요.
이 API는 InnoDI 7.0에 포함되며, 릴리스에서 공개 API baseline과 지원 Apple
toolchain 검사를 계속 수행합니다.


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
| `async` 또는 `async throws`, `.onDemand` | 거부 | 거부 | 허용 |

`Lazy<T>`와 `Provider<T>`는 동기 deferred wrapper입니다. Async target은
거부됩니다.

`asyncFactory:`로 만드는 `.shared` provider는 어떤 읽기보다 먼저 컨테이너
initializer 안에서 생성 task를 시작하고, 컨테이너는 그 task를 취소하지
않습니다. 그래서 `.transient` `@SubContainer`를 읽을 때마다 자식의 eager 비동기
작업이 다시 시작됩니다. 첫 읽기에서 생성하려면 `initialization: .onDemand`를
추가하세요. 이 provider의 accessor는 항상 throw하며, 생성된
`closeAsyncProviders()`가 진행 중인 작업을 취소하고 provider를 닫습니다. 취소
계약과 대안은
[비동기 shared 수명](Sources/InnoDI/InnoDI.docc/ko.lproj/Provide.md#비동기-shared-수명)을
참고하세요.

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
local availability 같은 graph-derived 검증만 건너뜁니다. 로컬 소유권 순환·선언 검증과 root 클로저 또는
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

타깃의 기본 격리가 MainActor라면 컨테이너에 `@MainActor`를 명시하거나
`@DIContainerRole(..., mainActor: true)`를 사용하세요. 호출자 격리를 따를
컨테이너라면 `nonisolated`를 선언합니다. 매크로는 이 타깃 설정을 추론하지
못합니다. 일반 async provider의 non-Sendable 결과를 actor에서 읽으려면
프로퍼티 선언에 `nonisolated(nonsending)`을 쓰세요.
[비동기 actor 읽기](Sources/InnoDI/InnoDI.docc/ko.lproj/Provide.md#actor에서-비동기-프로퍼티-읽기)를 참고하세요.

중요한 점:

- input-only container도 비어 있는 builder를 합성합니다.
- child container가 input-only여도 `<name>Overrides` 클로저는 컴파일되며,
  child에 override 가능한 멤버가 생기기 전까지는 no-op으로 동작합니다.
- 컨테이너는 nested `Overrides` 타입을 직접 선언하면 안 됩니다. InnoDI 6.0은
  부분적이고 mount 불가능한 API를 생성하는 대신 이 충돌을 오류로 거부합니다.

## `Lazy<T>`와 `Provider<T>`

비순환 그래프에서 지연 참조가 필요하면 `Lazy<T>`를 사용합니다.
6.0은 `Lazy<T>` / `Provider<T>`가 포함된 순환도 거부합니다.
지연 생성은 소유권 순환을 끊지 않으며 `validateDAG: false`도 이를 허용하지 않습니다.

`.transient` 의존성을 호출할 때마다 다시 진입해야 하면 `Provider<T>`를
사용합니다.

```swift
@Provide(.shared, factory: { (service: Lazy<Service>) in
    Consumer(service: service)
})
var consumer: Consumer
```

```swift
// 동기 .transient target의 이름은 `request`입니다.
@Provide(.shared, factory: { (request: Provider<Request>) in
    RequestLogger(requests: request)
})
var logger: RequestLogger
```

두 wrapper 자체는 값을 cache하지 않습니다. `Lazy<T>`는 target의 shared 또는
transient scope를 따르고, `Provider<T>`는 transient target만 허용합니다.
transient 값 override는 매번 같은 저장된 값을 반환합니다. 새 instance의 identity는
wrapper 자체가 아니라 live factory가 결정합니다.

두 wrapper 모두 의도적으로 non-`Sendable`이며, 컨테이너가 가진 원래 격리
도메인 안에 머물러야 합니다. 또한 둘 다 동기 wrapper이므로
`asyncFactory` 멤버를 target으로 삼을 수 없습니다.

## Nested Container와 Hierarchy

`@SubContainer`는 parent가 소유하는 child container를 모델링합니다.

```swift
@SubContainer(scope: .shared, with: [\Self.config, \Self.apiClient])
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
- `with:`와 `bindings:`의 `parent:` 쪽 key path는 직접 멤버 하나를
  `\Self.member`로 지정합니다. `\AppContainer.member` 같은 이름 있는 루트는
  `sub.noncanonical-parent-key-path`와 fix-it으로 거부되고, 중첩 컴포넌트는
  잘못된 wiring입니다. `child:` 쪽은 child container 타입(모듈 한정 가능)을 통해
  child input을 지정합니다.
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
  default 또는 named feature-root helper를 생성합니다. identity/close host
  overload를 추가하려면 `FeatureRoot(RootView.self, hosted: true)`를 쓰고 해당
  파일에서 `SwiftUI`와 `InnoDISwiftUI`를 import하세요. 모듈이 설치됐다는 이유만으로
  helper가 달라지지 않으며, 기존 0-argument helper도 유지됩니다.
- `DIContainerHost`는 fixed/assisted child를 route, document, window identity별로
  지연 생성해 소유합니다. 앱이 loading/failure/retry UI를 구성하고,
  `onDisappear` 대신 실제 close 경로에서 lifecycle handle을 호출합니다.
- `#PreviewWithContainer`도 같은 lazy owner를 사용하며 동일 payload의 preview를
  preview instance별로 분리합니다.
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
swift run InnoDI-DependencyGraph --root . --why provider:App.AppContainer.client
swift run InnoDI-DependencyGraph --root . --unused
```

target-scoped JSON 그래프 artifact 두 개 비교:

```bash
swift run InnoDI-DependencyGraph --diff before.json after.json
swift run InnoDI-DependencyGraph --diff before.json after.json --check-contract
```

`--check-contract`는 scope, container, provider, edge 계약이 하나라도 바뀌면
종료 코드 5를 반환하므로 CI에서 검토된 그래프 스냅샷 갱신만 허용할 수
있습니다. schema v6 provider 레코드는 타입, lifetime, 초기화 정책, 격리,
effect, canonical wiring, 명시적 collection 계약을 포함하며 source 줄/열
이동만으로는 계약 변경이 되지 않습니다.
이전 graph schema는 unchanged로 취급하지 않고 명시적으로 거부합니다.
존재하지 않거나 다른 container에 속한 참조, 잘못된 child ownership,
누락된 child input binding도 self-diff를 포함해 거부합니다.
질의는 각 child mount·assisted factory의 parent binding을 따라가며,
같은 child type을 여러 번 mount해도 연결을 합치지 않습니다.

`--why App.AppContainer.client`처럼 provider selector도 `--why`와
`--dependents`에서 사용할 수 있습니다. 결과는 provider 계약과 source 위치를
포함합니다. qualifier 없는 selector는 container/provider namespace를 함께
확인합니다. 충돌하면 양쪽 후보를 보여 주며 `container:<selector>` 또는
`provider:<selector>`로 명시해야 합니다. Exact graph ID의 직접 조회 동작은
유지됩니다. runtime cache/override/async provenance는 opt-in `DITraceContext`와
`DIBoundedTraceBuffer`로 수집하며, 비활성 경로에서는 ID, event, buffer를 만들지
않고 입력값이나 오류 payload도 기록하지 않습니다. graph artifact의 target ID를
`DITraceContext(sink:targetIDsByModule:generation:)`에 넣고 생성 컨테이너의
`_innoDITrace:` 인자로 context를 전달합니다.

생성된 eager, on-demand, transient, async, override, cache-hit, wait 경로가 이제
자동으로 event를 보냅니다. runtime module에 target mapping이 있으면
`providerID`는 schema-v6 graph ID와 일치하고, 없으면 reflection으로 얻은
module-qualified container path를 사용합니다. `ownerID`는 컨테이너 인스턴스,
`generation`은 재생성 세대, `instanceID`는 start와 terminal/cache/wait event를
연결합니다. wait event는 관련 provider와 instance도 기록합니다. InnoDI는
service factory 내부에서 시작한 task를 추적하지 않습니다. 생성 코드 밖의
경계는 `withResolution(providerID:)`와 `record`로 직접 계측할 수 있습니다.

migration 또는 도입 전 read-only doctor를 실행합니다.

```bash
swift run InnoDI-Doctor --root .
swift run InnoDI-Doctor --root . --json
```

기본 모드는 resolve, build, write, cache 삭제, process 종료를 하지 않습니다.
Swift package에서는 literal target source root와 plugin 배열을 parse하므로 주석,
문자열, 다른 target의 plugin이 누락을 가릴 수 없습니다. Dynamic manifest와 Tuist
target mapping은 healthy가 아니라 분석 불완전으로 남깁니다. migration 검사가 자기
모듈 때문에 `migrate.unqualified-ownership-ambiguous`를 보고하면
`InnoDI-Migrate`에 주는 `--trust-module <name>` 옵션을 그대로 넘기세요.
`--apply`는 migrator의 atomic exchange 검사를 사용합니다. 성공해도 이전 파일을 `RECOVERY` 경로에
보존하므로 editor를 닫고 두 파일을 검토한 뒤 불필요한 복사본만 삭제하세요.
POSIX mode는 유지하지만 ACL/xattr 보존이나 파일시스템 전체 트랜잭션은 보장하지 않습니다.
SwiftPM `--verify`는 `swift build`를 실행하고,
Tuist 검증은 generate 후 `--scheme`과 `--destination`이 모두 명시된 경우에만 실제
compile을 실행합니다. schema-v3 report는 migration 복구 경로와 generation/compilation의 exit, timeout,
log tail을 분리해 generation만 성공한 상태를 build 성공으로 합산하지 않습니다.

## Collection 조합

`@Multibinding([])`은 명시적 empty collection입니다. nonempty array는 생성된
Swift array를 compiler assignability witness로 사용하므로 문자열 타입 추정
없이 concrete 구현을 existential element로 합성할 수 있습니다.
`DICollectionGroup`과 `DIKeyedCollection`은 명시적으로 export한 module 출력을
호출자 순서로 합치고 keyed collision을 거부합니다. `DIProviderCollection`과
`DIKeyedProviderCollection`은 선택한 index 또는 key만 resolve합니다.

factory로 만든 collection은 `@Provide(collection:)`의 닫힌 graph 계약을
공개할 수 있습니다. `.ordered`, `.keyed`, `.providers`, `.keyedProviders`와
literal `\Self.member` contributor를 사용하고 keyed entry는
`.init(key: "id", contributor: \Self.member)`로 선언합니다. explicit empty도
유효합니다. Graph JSON schema v6는 factory body나 module을 검색하지 않고
key·순서·canonical contributor·contributor lifetime을 기록합니다. 중복 key는
last-wins 대신 실패합니다.

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
않습니다. Swift 6.4에서도 compiler dump가 보이도록 이 검사 빌드는 SwiftPM의
native backend를 선택합니다. 선택한 target이 실제로 매크로를 호출해야 하며,
선언만 빌드하면 확장 결과가 나오지 않습니다.
선언 하나만 볼 때는 Xcode의 **Expand Macro**가 가장 빠르고, 이
명령은 target 전체를 리뷰 가능한 artifact로 남길 때 사용합니다.

DocC 생성:

```bash
Tools/generate-docc.sh
```

릴리즈 노트와 업그레이드 노트는 [CHANGELOG.md](CHANGELOG.md)에 모여 있습니다.

## AI 에이전트 스킬

[InnoDI 스킬](skills/innodi/SKILL.md)은 AI 코딩 도구가 소비 프로젝트의 실제
resolved InnoDI API에 맞는 코드를 작성하도록 돕습니다. 스킬 원본·참고 문서·
정확한 릴리스에 고정한 소비 예제는 라이브러리와 함께 이 저장소에서 관리합니다.
Codex/Claude Code 단독 설치, 관리 원칙, 현재 평가 범위는
[설치·검증 안내](skills/README.md)를 참고하세요.
스킬은 안정 릴리스 InnoDI 7.0.x(`>=7.0.0, <7.1.0`)를 지원하며, 정확한
릴리스에 고정한 소비 예제는 7.0.0에서 검증했습니다. Swift 패키지 의존성을
추가하는 것만으로 AI 도구에 스킬이 설치되지는 않습니다.

## 예제

- [Examples/README.md](Examples/README.md)
- [Examples/SwiftUIExample](Examples/SwiftUIExample)
- [Examples/PreviewInjectionExample](Examples/PreviewInjectionExample)
- [Sources/InnoDIExamples/main.swift](Sources/InnoDIExamples/main.swift)
- [InnoSample](https://github.com/InnoSquadCorp/InnoSample): InnoDI를 InnoFlow,
  InnoNetwork, InnoRouter와 함께 쓰는 멀티 모듈 Tuist 앱
