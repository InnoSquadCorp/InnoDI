# InnoDI (한국어)

[English README](README.md)

Swift Macro 기반의 타입 안전한 의존성 주입 라이브러리입니다.

## 주요 기능

- 컴파일 타임 검증: 매크로 기반 진단으로 설정 오류를 빠르게 탐지
- 보일러플레이트 최소화: `init(...)` 자동 생성
- 스코프 지원: `shared`, `input`, `transient`
- AutoWiring: `Type.self` + `with:`로 간결한 선언
- 엄격한 이름 기반 해석: 팩토리 파라미터와 `with:` 의존성은 멤버 이름으로만 해석
- Init Override: 테스트 시 의존성 직접 주입 가능 (위치 파라미터 + 명명 `Overrides` 빌더 + `withOverrides` 스코프 헬퍼)
- DIP 지향: concrete 타입 사용 시 `concrete: true` 명시 강제

## 설치

`Package.swift`에 추가:

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "3.0.1")
]
```

타겟 의존성 추가:

```swift
.target(
    name: "YourApp",
    dependencies: ["InnoDI"]
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
    func fetch() async throws -> Data { /* ... */ }
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

복잡한 생성은 팩토리 클로저 사용:

```swift
@Provide(.shared, factory: { (baseURL: String) in
    APIClient(baseURL: baseURL, timeout: 30)
})
var apiClient: any APIClientProtocol
```

## Start Here

처음 보는 사용자는 아래 순서로 읽는 것을 권장합니다.

1. 이 README에서 설치, 컨테이너 문법, 지원 모델을 먼저 확인합니다.
2. [Validation](Sources/InnoDI/InnoDI.docc/Validation.md) 에서 local/build/global validation과 observability artifact를 확인합니다.
3. [PolicyBoundaries](Sources/InnoDI/InnoDI.docc/PolicyBoundaries.md) 에서 정확한 matching 규칙, 제외 규칙, fallback 동작을 확인합니다.
4. [ModuleWideInitDetection](Sources/InnoDI/InnoDI.docc/ModuleWideInitDetection.md) 에서 custom `init` 제한 정책을 확인합니다.

릴리스/운영 문서:

- [CHANGELOG.md](CHANGELOG.md)
- [RELEASING.md](RELEASING.md)
- [MIGRATION.md](MIGRATION.md)

## API 요약

### `@DIContainer`

```swift
@DIContainer(validate: Bool = true, root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

`@DIContainer`가 붙은 타입과 extension 전체에서 사용자 정의 `init`을 지원하지 않습니다.
매크로는 type body와 같은 파일의 동일 타입 extension을 막고, build plugin은 다른 파일의 extension까지 같은 규칙으로 확장합니다.
생성된 init을 사용하거나, 수동 wiring이 필요하면 매크로를 제거해야 합니다.

`@DIContainer`는 아래 네 종류 선언을 생성합니다:

1. primary `init(...)` — 필수 `.input` 파라미터 + optional `.shared`/`.transient` override 파라미터
2. `.shared` / `.transient` 멤버가 하나라도 있을 때 nested `struct Overrides`
   (아래 [Overrides 빌더로 테스트하기](#overrides-빌더로-테스트하기) 참고)
3. convenience `init(<inputs…>, _ applyOverrides: (inout Overrides) -> Void)` — 명명 override를 primary init으로 연결
4. sync / throws / async / async throws 4가지 effect 조합의
   `static func withOverrides<T>(<inputs…>, _ applyOverrides:, operation:)`

input-only 컨테이너, 그리고 사용자가 직접 `Overrides` 타입을 선언한 컨테이너는
빌더 생성을 생략합니다 (뒤 [사용자 정의 `Overrides` 충돌](#사용자-정의-overrides-충돌) 참고).

| 파라미터 | 기본값 | 설명 |
|---|---|---|
| `validate` | `true` | 호환성 유지를 위한 플래그입니다. `.shared`/`.transient`의 factory 요구사항, `.input` 제약, `concrete: true` opt-in 같은 핵심 생성 불변식은 값과 무관하게 컴파일 타임에 계속 강제됩니다. |
| `root` | `false` | CLI 그래프에서 루트 컨테이너로 표시할지 여부 |
| `validateDAG` | `true` | 이 컨테이너의 DAG 검증 참여 여부. `false`면 DAG 검증에서 제외 |
| `mainActor` | `false` | 생성되는 init/accessor에 `@MainActor` 격리를 적용 |

### `@Provide`

```swift
@Provide(_ scope: DIScope = .shared, _ type: Type.self? = nil, with: [KeyPath] = [], factory: Any? = nil, asyncFactory: Any? = nil, concrete: Bool = false)
```

| 파라미터 | 기본값 | 설명 |
|---|---|---|
| `scope` | `.shared` | 라이프사이클 스코프 |
| `type` | `nil` | AutoWiring용 concrete 타입 |
| `with` | `[]` | AutoWiring 의존성 키패스 목록 |
| `factory` | `nil` | 생성식 (또는 클로저) |
| `asyncFactory` | `nil` | 비동기 생성 클로저 (`factory`와 동시 사용 불가) |
| `concrete` | `false` | concrete 타입 사용 시 명시적 opt-in |

## 스코프 규칙

| 스코프 | 의미 | factory 필요 여부 |
|---|---|---|
| `.input` | 컨테이너 생성 시 외부 주입 | 필요 없음 |
| `.shared` | 컨테이너 생명주기 동안 1회 생성/재사용 | 필요 |
| `.transient` | 접근할 때마다 새로 생성 | 필요 |

### Async Factory

비동기 생성이 필요하면 `asyncFactory`를 사용합니다.

```swift
@Provide(.shared, asyncFactory: { (config: AppConfig) async throws in
    try await APIClient.make(config: config)
})
var apiClient: any APIClientProtocol
```

규칙:

- `factory`와 `asyncFactory`는 동시에 사용할 수 없습니다.
- `.input` 스코프에서는 `asyncFactory`를 사용할 수 없습니다.
- `asyncFactory`는 반드시 `async` 클로저여야 합니다.

## AutoWiring

```swift
@DIContainer
struct AppContainer {
    @Provide(.input)
    var config: AppConfig

    @Provide(.input)
    var logger: Logger

    @Provide(.shared, APIClient.self, with: [\.config, \.logger])
    var apiClient: any APIClientProtocol
}
```

- `with:`의 프로퍼티 이름은 실제 이니셜라이저 파라미터 이름과 맞아야 합니다.
- 이름이 다르거나 변환이 필요하면 팩토리 클로저를 사용하세요.

## DIP(의존성 역전) 규칙

- `.shared`/`.transient`의 프로토콜 타입은 `any Protocol`처럼 명시적 existential 표기를 사용하세요.
- concrete 타입은 `concrete: true`를 명시해야 합니다.

```swift
@DIContainer
struct AppContainer {
    @Provide(.shared, factory: APIClient())
    var apiClient: any APIClientProtocol

    @Provide(.shared, factory: URLSession.shared, concrete: true)
    var session: URLSession
}
```

## Init Override (테스트 주입)

생성된 init은 `.shared`/`.transient`에 대해 optional override 파라미터를 제공합니다.

```swift
@DIContainer
struct AppContainer {
    @Provide(.input)
    var baseURL: String

    @Provide(.shared, factory: APIClient(baseURL: baseURL))
    var apiClient: any APIClientProtocol
}

let prod = AppContainer(baseURL: "https://api.example.com")
let test = AppContainer(baseURL: "https://test.example.com", apiClient: MockAPIClient())
```

생성 시그니처 예:

```swift
init(baseURL: String, apiClient: (any APIClientProtocol)? = nil)
```

## Overrides 빌더로 테스트하기

`.shared` / `.transient` 멤버가 하나라도 있으면, `@DIContainer`는 위 위치
파라미터 외에 **명명 override** 빌더도 함께 생성합니다. 테스트가 바꾸려는
멤버만 지정하면 나머지는 그대로 원래 factory로 해석됩니다.

### 트레일링 클로저 convenience init

```swift
@DIContainer
struct AppContainer {
    @Provide(.input)
    var baseURL: String

    @Provide(.shared, factory: { APIClient(baseURL: baseURL) })
    var apiClient: any APIClientProtocol

    @Provide(.transient, factory: { (apiClient: any APIClientProtocol) in
        HomeViewModel(api: apiClient)
    }, concrete: true)
    var homeViewModel: HomeViewModel
}

let container = AppContainer(baseURL: "https://test.example.com") {
    $0.apiClient = MockAPIClient()
}
// container.apiClient 는 MockAPIClient
// container.homeViewModel 은 mock 을 타고 흐른 상태로 해석됨
```

shared override는 downstream transient factory에도 전파됩니다.

### `withOverrides` 스코프 연산

`swift-dependencies`의 `withDependencies { } operation:` 스타일과 동일하게,
override 수명을 하나의 연산에 묶고 싶을 때 사용합니다:

```swift
let result = try await AppContainer.withOverrides(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
} operation: { container in
    try await container.homeViewModel.load()
}
```

4가지 effect 조합이 모두 생성되므로 sync 호출에서 `try await`를 붙일 필요는
없습니다:

| 오버로드 | 시그니처 형태 |
|---|---|
| sync, non-throwing | `(Container) -> T` |
| sync, throwing | `(Container) throws -> T` |
| async, non-throwing | `(Container) async -> T` |
| async, throwing | `(Container) async throws -> T` |

생성되는 모든 선언은 컨테이너의 access level을 미러링하고 (`public` 컨테이너
→ `public` 빌더), `@MainActor` 컨테이너에는 `@MainActor`가 전파됩니다.

### async `.shared` override

`asyncFactory`로 선언된 `.shared` 멤버도 빌더에서는 평범한 옵셔널
(`var apiClient: APIClient? = nil`) 로 노출됩니다. `Task<…>` 로 감쌀 필요가
없고, 생성 시점에 값만 넘기면 primary init이 동일한 task-backed accessor로
감싸 줍니다.

### `.transient` override는 저장값을 반환

`.transient` override는 매 접근 때 **같은 저장값을 그대로 반환**합니다.
테스트에서 특정 값을 고정해두고 assertion 하기 쉬운 의도된 동작입니다.

### 사용자 정의 `Overrides` 충돌

컨테이너 내부에 이미 `Overrides` 타입(struct/class/enum/actor/typealias)이
있으면 매크로는 `container.overrides-name-conflict` 경고를 발행하고
`Overrides` / convenience init / `withOverrides` 생성을 **전부 생략**합니다.
primary init만 그대로 생성되므로 기존 호출부는 영향이 없습니다. 빌더 API를
되살리려면 사용자 정의 타입을 rename 하거나 제거하면 됩니다.

## `Lazy<T>`로 순환 끊기

`@DIContainer`는 엄격한 DAG을 강제합니다. 두 컨테이너 멤버의 factory가
서로를 참조하면 `container.dependency-cycle` 진단이 발생하고 컴파일이 실패
합니다. 구조 리팩토링이 답인 경우가 많지만, coordinator ↔ view model처럼
본질적으로 양방향인 경우도 있습니다. 이런 경우를 위해 InnoDI는 `Lazy<T>`
탈출구를 제공합니다.

```swift
import InnoDI

@DIContainer
struct AppContainer {
    @Provide(.shared, factory: { (b: InnoDI.Lazy<CoordinatorB>) in CoordinatorA(b: b) }, concrete: true)
    var a: CoordinatorA

    @Provide(.shared, factory: { (a: CoordinatorA) in CoordinatorB(a: a) }, concrete: true)
    var b: CoordinatorB
}

final class CoordinatorA {
    let b: InnoDI.Lazy<CoordinatorB>
    init(b: InnoDI.Lazy<CoordinatorB>) { self.b = b }
    func resolveB() -> CoordinatorB { b() }
}

final class CoordinatorB {
    let a: CoordinatorA
    init(a: CoordinatorA) { self.a = a }
}
```

### 동작 방식

- `Lazy<T>`는 `@Sendable () -> T` resolver를 감싼 값 타입입니다. `b()` 호출
  시점에 이미 초기화된 storage를 돌려줍니다 (`.shared` 캐싱 외 별도 캐싱
  없음).
- Factory 파라미터 타입이 `Lazy<T>`이면 해당 엣지는 **soft edge**로 분류
  됩니다. 컨테이너 단위 cycle 검출(`container.dependency-cycle`)과 CLI의
  `--validate-dag` 전역 검증에서 모두 제외되며, 그래프 렌더링에는 dashed로
  표시됩니다.
- 생성 코드는 soft-target 멤버마다 `let _lazyCell_<name> = _LazyCell<T>()`을
  init 상단에 선언하고, factory 호출 시 사용자가 적은 `Lazy` 표기
  (예: `InnoDI.Lazy`) 그대로 `Lazy({ cell.resolve() })`를 전달한 뒤,
  shared/input 값은 즉시 저장하고 transient 타깃은 init 종료 직전에
  resolver를 바인딩합니다. 덕분에 struct 컨테이너도 factory 호출 시점에는
  `self`를 캡처하지 않고 형제 멤버를 forward-reference할 수 있습니다.
- `Lazy<T>` resolver를 받는 멤버는 타깃 멤버보다 **먼저** 선언돼야 init 순서
  상 `_LazyCell`이 이미 존재합니다.
- `container.dependency-cycle` 진단 메시지 끝에
  _"To break this cycle without restructuring, wrap one factory parameter in `Lazy<T>`."_
  가 추가됐습니다.

### 주의할 점

- 감지는 AST 텍스트 기반입니다. `Lazy<Foo>`, `InnoDI.Lazy<Foo>`, 그리고
  member-qualified `Something.Lazy<Foo>` 모두 soft-edge로 처리됩니다.
  `typealias Lazy = MyOwnType` 같은 재명명은 매크로가 해석하지 못합니다.
  생성 코드도 사용자가 적은 qualifier를 그대로 보존하므로, 동명의 타입이
  이미 있다면 `InnoDI.Lazy<Foo>`를 권장합니다.
  [MIGRATION.md](MIGRATION.md)를 참고하세요.
- `.transient`와 함께 써도 안전하며, `a()`마다 새 인스턴스가 생성됩니다.
  `Lazy<Self>`도 허용되지만, 실제로 동작할지는 factory 구현에 달려 있습니다
  (`.transient` self-reference는 무한 재귀).
- `Lazy<T>` 자체는 동기 resolver이므로 `asyncFactory`로 생성되는 `.shared`
  멤버는 soft target으로 받을 수 없습니다.

## Dependency Graph CLI

InnoDI는 컨테이너 관계를 시각화하는 CLI를 제공합니다.

```bash
swift run InnoDI-DependencyGraph --root /path/to/your/project
```

포맷:

```bash
swift run InnoDI-DependencyGraph --root /path/to/your/project --format mermaid
swift run InnoDI-DependencyGraph --root /path/to/your/project --format dot --output graph.dot
swift run InnoDI-DependencyGraph --root /path/to/your/project --format ascii
```

PNG 출력(Graphviz 필요):

```bash
swift run InnoDI-DependencyGraph --root /path/to/your/project --format dot --output graph.png
```

DAG 검증:

```bash
swift run InnoDI-DependencyGraph --root /path/to/your/project --validate-dag
```

CLI 동작 요약:

- `@DIContainer` 선언과 `.input` 요구값을 수집
- 컨테이너 내부 생성 호출에서 container-to-container 엣지 추출
- stable identity(`relativeFilePath#declarationPath`)로 동일 이름 컨테이너 오병합 방지
- 대상 컨테이너가 이름 충돌로 모호하면 엣지 생성을 생략
- `--validate-dag` 모드에서는 순환/모호성 발견 시 종료 코드 `3`으로 실패

검증 보정 사항:

- `@DIContainer(validateDAG: false)`로 표시된 컨테이너는 `--validate-dag`에서 순환/모호성 판정 모두에서 완전 제외됩니다.
- 매크로 내부 순환 검증용 의존성 추출은 AST 기반으로 동작하며, 문자열 리터럴 토큰으로 인한 오탐 사이클을 방지합니다.

## DocC 문서

로컬 DocC 문서 생성:

```bash
Tools/generate-docc.sh
```

온라인 DocC (GitHub Pages):

- https://innosquadcorp.github.io/InnoDI/documentation/innodi/

`.github/workflows/docs.yml` 동작:

- `pull_request`: `innodi-docc` 아티팩트를 업로드합니다.
- `main` 브랜치 `push`: GitHub Pages로 DocC 사이트를 배포합니다.

처음 Pages를 연결하는 저장소라면, Repository Settings에서 Pages Source를
`GitHub Actions`로 설정해야 합니다.

## License

MIT

[LICENSE](LICENSE) 파일을 참고하세요.

## Build Tool Plugin

InnoDI는 DAG 검증용 SwiftPM 플러그인을 제공합니다.

- `InnoDIDAGValidationPlugin`

이 플러그인은 패키지 입력 상태별로 검증을 한 번만 수행하고, 같은 결과를 타깃 간에 재사용합니다.
즉, 각 타깃마다 전체 패키지 그래프를 다시 스캔하지 않습니다.

타깃에 연결 예시:

```swift
.target(
    name: "YourApp",
    dependencies: ["InnoDI"],
    plugins: [
        .plugin(name: "InnoDIDAGValidationPlugin", package: "InnoDI")
    ]
)
```

## 확장 예제

- `Examples/SwiftUIExample` - 단일 feature root에서 navigation, loading skeleton, recoverable error/retry, cancellation을 로컬 `@Observable` 상태로 관리
- `Examples/TCAIntegrationExample`
- `Examples/PreviewInjectionExample` - preview/live/failure 루트가 여러 서비스를 environment 경계에서 교체하며 richer preview matrix를 보여줌
- `Examples/SampleApp`

## 매크로 성능 회귀 체크

매크로 테스트 성능 회귀를 스크립트로 점검할 수 있습니다.

```bash
Tools/measure-macro-performance.sh
```

의도적으로 성능 특성이 바뀐 경우 baseline 갱신:

```bash
Tools/measure-macro-performance.sh --iterations 5 --update-baseline
```

기본 baseline 파일:

- `Tools/macro-performance-baseline.json`

## 벤치마크

10/50/100/250 dependency 시나리오 벤치 실행:

```bash
Benchmarks/run-compile-bench.sh
Benchmarks/run-runtime-bench.sh
Benchmarks/compare.sh
```

결과 JSON:

- `Benchmarks/results/compile.json`
- `Benchmarks/results/runtime.json`
- `Benchmarks/results/compare.json`

Needle/SafeDI 비교 항목은 현재 non-blocking 스캐폴드로 리포트에 표시됩니다.
