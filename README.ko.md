# InnoDI (한국어)

[English README](README.md)

Swift Macro 기반의 타입 안전한 의존성 주입 라이브러리입니다.

## 주요 기능

- 컴파일 타임 검증: 매크로 기반 진단으로 설정 오류를 빠르게 탐지
- 보일러플레이트 최소화: `init(...)` 자동 생성
- 스코프 지원: `shared`, `input`, `transient`
- AutoWiring: `Type.self` + `with:`로 간결한 선언
- Init Override: 테스트 시 의존성 직접 주입 가능
- DIP 지향: concrete 타입 사용 시 `concrete: true` 명시 강제

## 설치

`Package.swift`에 추가:

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "1.0.0")
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

## API 요약

### `@DIContainer`

```swift
@DIContainer(validate: Bool = true, root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

| 파라미터 | 기본값 | 설명 |
|---|---|---|
| `validate` | `true` | 스코프/팩토리 검증 활성화. `false`일 때 `.shared`/`.transient` 누락 팩토리는 런타임 `fatalError` fallback으로 처리. `.input`의 factory 금지와 concrete opt-in 규칙은 계속 강제됨. |
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

CI에서는 `.github/workflows/docs.yml`에서 DocC 아티팩트를 업로드합니다.

## Build Tool Plugin

InnoDI는 DAG 검증용 SwiftPM 플러그인을 제공합니다.

- `InnoDIDAGValidationPlugin`

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

- `Examples/SwiftUIExample`
- `Examples/TCAIntegrationExample`
- `Examples/PreviewInjectionExample`
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
