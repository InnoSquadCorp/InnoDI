# InnoDI

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

컴파일 타임과 빌드 타임 검증, dependency graph 도구, hierarchy 검증,
SwiftUI helper를 함께 제공하는 Swift용 매크로 기반 DI 프레임워크입니다.

## 왜 InnoDI인가

InnoDI는 DI wiring을 명시적이고 리뷰 가능한 상태로 유지하면서, 실패를 더
이른 단계에서 발견하고 싶은 팀을 위한 도구입니다.

- `@DIContainer`와 `@Provide`가 일반 Swift 타입에서 컨테이너 API를 생성합니다.
- 매크로 검증이 로컬 실수를 확장 시점에 잡습니다.
- build validation과 graph CLI가 cross-file, cross-module, global graph 문제를 잡습니다.
- `InnoDISwiftUI`가 루트 경계의 반복적인 environment wiring을 줄여줍니다.

InnoDI는 runtime state machine이 아닙니다. 런타임 상태는 앱 레이어나
`InnoFlow`, `InnoRouter`, `InnoNetwork` 같은 companion framework에 두는
것을 전제로 합니다.

## 요구 사항

- Swift tools version `6.2`
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

## 설치

`Package.swift`에 InnoDI를 추가합니다.

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "4.1.0")
]
```

그 다음 필요한 product를 타깃에 연결합니다.

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI",
        "InnoDISwiftUI"
    ]
)
```

SwiftUI helper를 사용하지 않으면 `InnoDI`만 import하면 됩니다.

InnoDI 컨테이너를 선언하는 타깃에는 build-time DAG validator 플러그인을
연결합니다.

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

## 빠른 시작

```swift
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
    @Provide(.input)
    var baseURL: String

    @Provide(.shared, APIClient.self, with: [\.baseURL])
    var apiClient: any APIClientProtocol
}

let container = AppContainer(baseURL: "https://api.example.com")
let client = container.apiClient
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
4. [Module-Wide Init Detection](Sources/InnoDI/InnoDI.docc/ko.lproj/ModuleWideInitDetection.md)
5. [RELEASING.md](RELEASING.md)
6. [ROADMAP.md](ROADMAP.md)

## 핵심 API

### `@DIContainer`

`@DIContainer`는 다음을 합성합니다.

1. 필수 `.input` 파라미터와 `.shared`, `.transient`, `@SubContainer`
   멤버용 optional override를 받는 primary `init(...)`
2. nested `Overrides` 타입
3. `init(<inputs...>, _ applyOverrides: (inout Overrides) -> Void)` 형태의 convenience init
4. `sync`, `throws`, `async`, `async throws` 4종류의 `withOverrides` overload

사용자가 직접 nested `Overrides` 타입을 선언하지 않는 한, 모든 컨테이너는
overrides scaffolding을 생성합니다.

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

| 파라미터 | 기본값 | 의미 |
|---|---|---|
| `root` | `false` | 그래프 렌더 엔트리 플래그입니다. 하나라도 root가 있으면 Mermaid, DOT, ASCII 출력은 root에서 도달 가능한 노드와 엣지 union만 남깁니다. |
| `validateDAG` | `true` | global DAG validation과 매크로의 local cycle 및 closure/`with:` 기반 graph-derived 검증을 켭니다. `false`면 그 범위만 건너뛰고, raw-expression `factory:`와 initializer reference 진단 및 구조 검증은 계속 유지됩니다. |
| `mainActor` | `false` | 생성되는 컨테이너 API에 `@MainActor` 격리를 적용합니다. UI 루트 컨테이너에 권장됩니다. |

`@DIContainer`는 annotated type이나 매칭되는 extension에 사용자 정의 `init`
선언을 허용하지 않습니다. 생성된 initializer를 사용하거나, 매크로 없이
수동으로 wiring해야 합니다.

### `@Provide`와 스코프

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    factory: Any? = nil,
    asyncFactory: Any? = nil,
    concrete: Bool = false
)
```

| 스코프 | 의미 | 생성 규칙 |
|---|---|---|
| `.input` | 컨테이너 생성 시 외부에서 주입하는 의존성 | `factory`, `asyncFactory` 불가 |
| `.shared` | 컨테이너 인스턴스당 1회 생성 후 재사용 | `factory`, `asyncFactory`, 또는 `Type.self` + `with:` 필요 |
| `.transient` | 접근할 때마다 새로 생성 | `factory`, `asyncFactory`, 또는 `Type.self` + `with:` 필요 |

추가 규칙:

- `factory`와 `asyncFactory`는 동시에 사용할 수 없습니다.
- `asyncFactory`는 반드시 `async` 클로저여야 합니다.
- concrete `.shared` / `.transient` 저장은 `concrete: true`가 필요합니다.
- factory 파라미터와 `with:` wiring의 이름 해석은 멤버 이름 기준으로 엄격하게 이뤄집니다.

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
매크로의 local cycle 및 closure/`with:` graph-derived 검증만 건너뜁니다.
구조 검증은 꺼지지 않고, raw-expression `factory:`나 initializer reference
진단도 계속 동작합니다.

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
- 컨테이너가 직접 nested `Overrides` 타입을 선언하면 매크로는 primary
  initializer만 남기고 생성된 builder surface는 건너뜁니다.

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
도메인 안에 머물러야 합니다.

## Nested Container와 Hierarchy

`@SubContainer`는 parent가 소유하는 child container를 모델링합니다.

```swift
@SubContainer(scope: .shared, withNames: ["config", "apiClient"])
var feature: FeatureContainer
```

핵심 규칙:

- `scope:`는 필수입니다.
- parent `@Provide` 후보가 0개 또는 1개일 때만 이름 기준 implicit wiring을 편의로 허용합니다.
- parent 후보가 여러 개면 `with:`, `withNames:`, `bindings:`로 명시 wiring해야 합니다.
- `with:` 또는 `withNames:`는 같은 이름 subset/order를 forward합니다.
- `bindings:`는 child input label과 parent member 이름이 다를 때 remap합니다.
- `with:`, `withNames:`, `bindings:` 중 정확히 하나의 wiring form만 사용합니다.
- parent의 `Overrides`에는 전체 교체 슬롯(`feature`)과 child override closure(`featureOverrides`)가 모두 추가됩니다.

cross-module ownership에는 다음을 사용합니다.

- mount 가능한 child container용 `@DIComponent`
- rooted workspace-level validation용 `@DIHierarchyRoot`

## SwiftUI Helper

`InnoDISwiftUI`는 컨테이너 계약 위에 작은 SwiftUI 통합 레이어를 더합니다.

- `.innodi(container)`는 생성된 environment bridge를 view tree에 적용합니다.
- `@DIEnvironmentBridge`는 container member를 SwiftUI environment key에 매핑합니다.
- `@DIFeatureRoot`는 child container의 default 또는 named feature-root helper를 생성합니다.

UI 루트 컨테이너에는 `@DIContainer(mainActor: true)`를 권장합니다.

## CLI와 릴리즈 표면

그래프 렌더링:

```bash
swift run InnoDI-DependencyGraph --root .
```

global DAG 검증:

```bash
swift run InnoDI-DependencyGraph --root . --validate-dag
```

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
