# Provide

`@Provide`는 컨테이너 멤버와 그 생성 전략을 선언합니다.

InnoDI 6.0에서 `@Provide`는 동일한 지원 `@DIContainer` struct의 직접적이고
평범한 stored instance `var`에만 붙일 수 있습니다. `let`, computed/observed
property, `lazy`, `weak`, `unowned`, `static`/`class`, standalone, 간접 nested
사용은 거부됩니다. 생성 accessor는 InnoDI가 소유하므로
`_InnoDIProvideAccessor`를 직접 붙이면 안 됩니다.

Property wrapper, conditional/unknown attribute, `private(set)` 같은 setter
access modifier, custom global-actor attribute도 거부됩니다. `@Provide` 외에 source에
직접 쓰는 property-level attribute는 허용되지 않으며 `@MainActor`도 포함됩니다.
Actor 격리는 `@DIContainerRole(role: ContainerRole.local, mainActor: true)`로 요청하세요. Provider 선언과
accessor에 InnoDI가 생성한 격리 attribute는 내부 compiler support입니다. 완전한
`@Provide` 멤버 선언을 `#if` 안에 두면
`provide.conditional-declaration-unsupported` 진단이 발생합니다.
선언은 조건 밖에 두고 factory 또는 주입 구현 내부에서 분기하세요.

프로퍼티마다 `@Provide`는 정확히 하나만 붙일 수 있으며 중복 attribute는
`provide.duplicate-attribute`로 거부됩니다. 명시적 property type은 opaque
`some Protocol`이나 implicitly unwrapped optional `T!`일 수 없습니다. 각각
`any Protocol`, 명시적인 `T` 또는 `T?`로 바꾸세요. Compiler-support accessor와
다른 property wrapper를 의도적으로 위조해 함께 붙이면 InnoDI misuse 진단과 함께
Swift 자체의 structural diagnostic도 발생할 수 있습니다.

## 선언

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    initialization: DIInitialization = .eager,
    effect: DIProviderEffect = .none,
    factory: Any? = nil,
    asyncFactory: Any? = nil
)
```

`effect:`는 추론된 동작이 아니라 명시적인 테스트·프리뷰 metadata입니다. 실제
네트워크, 영속 저장소, 프로세스, 디바이스처럼 외부에서 관찰 가능한 provider는
`.sideEffect`로 표시하세요. 그러면 생성된 `Overrides`가 opt-in
`InnoDITesting` 검증에 필요한 override를 노출합니다. 기본 `.none`은 “strict
override가 필요하다고 분류하지 않음”이라는 뜻이며 opaque factory가 순수하다는
증명이 아닙니다. Production 생성에는 strict 검증이 자동 적용되지 않습니다.

## Input 값과 escaping 함수

생성되는 `@Input` initializer 파라미터는 선언 타입 `T`의 eager 값입니다. Swift는
initializer 호출 전에 각 인자를 평가하므로 `try makeValue()`와
`await makeValue()`를 그대로 인자 식으로 사용할 수 있습니다. 직접 표기한
non-optional function type은 자동 감지해 escaping 파라미터로 생성합니다.
Non-optional function type이 typealias 뒤에 숨었다면
`@Input(escaping: true)`를 선언하세요.

`escaping:`은 literal Bool이어야 하고 `@Input`에서만 유효합니다. 명백한
nonfunction 또는 optional-function type 형태는 안정적인 InnoDI 진단으로
거부됩니다. Attached macro는 임의 alias를 해석할 수 없어 identifier/member type을
보수적으로 허용하므로, 실제 alias가 non-optional function type이 아니면 Swift
자체 진단이 추가될 수 있습니다.

## 생성 방식

- `factory`: 동기 생성식 또는 클로저
- `asyncFactory`: 비동기 생성 클로저
- `Type.self`, 선택적 `with:`: 동기 생성/autowiring
- property initializer: 동기 opaque 생성

`.shared`와 `.transient`는 네 방식 중 정확히 하나를 선택합니다. `@Input`은
아무 생성 방식도 선택하지 않고 `with:`도 사용하지 않습니다.

## 규칙

- `factory:`, `asyncFactory:`, `Type.self`, property initializer는 서로 배타적인
  생성 source입니다.
- `@Input`은 모든 생성 source와 `with:`를 허용하지 않습니다.
- `.shared`와 `.transient`는 정확히 하나의 생성 source가 필요합니다.
- `with:`는 `Type.self`와 동기 provider에서만 사용할 수 있습니다.
- `asyncFactory`는 `.shared`와 `.transient`에서 지원되며 `async`
  클로저여야 합니다.
- 선언된 property type이 storage shape을 결정합니다. Concrete nominal type은
  concrete storage를, `any Protocol`은 existential storage를 사용합니다.
- factory 파라미터와 `with:` 의존성은 멤버 이름 기준으로 엄격하게 해석됩니다.

## Sibling edge 계약

- root `factory:` 또는 `asyncFactory:` 클로저 리터럴의 이름 있는 파라미터만
  sibling edge를 선언합니다. Nested 클로저와 임의 identifier는 edge를 만들지
  않습니다.
- `Type.self`는 literal `with:` 배열에서 edge를 선언합니다. 각 항목은
  `with: [\Self.config]`처럼 정확히 canonical direct-member 표기인
  `\Self.member`여야 하며 `with: []`도 유효합니다. 이름이 있는 container,
  module-qualified, typealias root와 nested component, optional chaining,
  subscript, 계산된 원소는 거부됩니다. 모든 target은 동기 생성 방식을 사용해야
  합니다.
- 클로저가 아닌 factory와 property initializer는 opaque한 zero-edge source이며
  sibling member를 참조할 수 없습니다. Root 클로저 파라미터 또는 qualified
  global/static symbol을 사용하세요.

## Provider 효과 호환성

Factory 효과는 명시적으로 선언하며 의존성에서 추론하지 않습니다. 비동기
consumer에는 `asyncFactory:`를 사용하고, throwing 비동기 provider를 소비한다면
클로저에 `async throws`를 명시하세요. 이 호환성은 `validateDAG: false`에서도
검증됩니다.

| Provider | sync consumer | `async` consumer | `async throws` consumer |
|---|---:|---:|---:|
| sync | 허용 | 허용 | 허용 |
| `async` | 거부 | 허용 | 허용 |
| `async throws` | 거부 | 거부 | 허용 |
| `async` 또는 `async throws`, `.onDemand` | 거부 | 거부 | 허용 |

비동기 on-demand provider를 읽으면 읽는 쪽의 취소나 닫힌 provider를 관찰할 수
있으므로, 이 provider의 consumer 효과는 항상 `async throws`입니다.

`Lazy<T>`와 `Provider<T>`는 동기 deferred wrapper로 유지됩니다. 두 wrapper 모두
`asyncFactory:`로 생성되는 target을 거부합니다. `with:`, `@Multibinding`
contributor, `@SubContainer` child input도 동기 parent member만 받습니다.

## Actor에서 비동기 프로퍼티 읽기

일반 nonisolated 컨테이너가 non-Sendable 입력을 보관하거나 transient 값으로
반환한다면 **프로퍼티 선언 전체**에 `nonisolated(nonsending)`을 쓰세요.
호출자 actor의 격리를 유지하면서 기존 읽기 문법을 사용할 수 있습니다.

```swift
@DIContainer
struct Services {
    @Input var box: Box
    @Provide(.transient, asyncFactory: { (box: Box) async in box })
    nonisolated(nonsending) var session: Box
}
// actor 안에서: let value = await services.session
```

같은 호출자 격리로 이어지는 async 의존성 프로퍼티에도 각각 modifier를 적용하세요.
이 문법은 컨테이너, 결과, 캡처한 의존성을 Sendable로 바꾸지 않습니다. Shared async
저장소의 결과는 여전히 Sendable이어야 합니다. 컨테이너가 별도의 동기
non-Sendable 입력을 보관하는 경우와 구분하세요. 일반 owned view의 async
프로퍼티에는 이미 이 modifier가 생성됩니다.

MainActor 컨테이너는 actor 격리를 유지하고 MainActor에서 읽으세요.
`mainActor: true` provider에는 이 opt-out을 추가하지 않습니다. 타깃의 기본
격리가 MainActor인 경우는 <doc:DIContainer>를 참고하세요. 별도 resolver
메서드 없이 `await services.session`을 계속 사용합니다.

## 타입으로 검사하는 동기 prewarm (7.0 후보)

`initialization: .onDemand`를 사용하는 동기 `.shared` provider가 있으면
컨테이너에 중첩 `_InnoDIPrewarmProvider: Sendable` enum이 생성됩니다. Case 이름은
해당 provider 이름이며 Swift 컴파일러가 선택을 검사합니다.

```swift
@DIContainer
struct FeatureContainer {
    @Provide(.shared, initialization: .onDemand, factory: Metrics())
    var metrics: Metrics
    @Provide(.shared, initialization: .onDemand, factory: Analytics())
    var analytics: Analytics
}

let container = FeatureContainer()
container.prewarm(.metrics)
container.prewarm(.analytics, .metrics)

// 빈 선택은 오류를 던지지 않고 아무 작업도 하지 않습니다.
container.prewarm()
```

타입 기반 메서드는 동기이며 오류를 던지거나 값을 반환하지 않습니다. 빈 선택은
아무 작업도 하지 않습니다. 각 선택은 인자 순서대로 해당 provider에 직접
전달됩니다. 7.0 후보는 기존 key path overload를 대체합니다.
반복 선택과 컨테이너 복사본은 기존 shared cache를 재사용합니다. 선택한 factory가
필요로 하지 않는 한, 선택하지 않은 provider는 생성되지 않습니다.

Input, eager, 비동기, transient provider에는 case가 없습니다. 다른 컨테이너의
선택은 서로 다른 Swift 타입입니다. 이 enum은 선택 전용이며 `get`, `resolve`,
등록 기능이나 런타임 registry를 제공하지 않습니다. Token은 `Sendable`이지만
provider 값까지 `Sendable`일 필요는 없습니다. 생성되는 prewarm 메서드는
컨테이너의 main actor 격리를 유지하며, 일반 동기 컨테이너의 값 접근은 호출한
쪽에서 실행됩니다.

Enum과 타입 기반 메서드는 생성되는 initializer 및 `Overrides`처럼 컨테이너의
접근 수준을 따릅니다. Getter의 접근 수준이 더 좁아도 case는 생성 대상의 이름을
노출하지만, case를 선택해서 값을 얻을 수는 없습니다. 명시적인 타입 annotation은
`FeatureContainer._InnoDIPrewarmProvider`로 작성합니다. `.metrics`처럼 문맥에서
추론하는 호출은 이 긴 compiler-owned 이름을 쓰지 않아도 됩니다.

`_InnoDI` 접두사는 이미 생성 지원 코드에 예약되어 있습니다. 이 접두사를 사용하는
직접 작성한 컨테이너 선언에는 `container.reserved-name-prefix` 진단이 발생합니다.
`PrewarmProvider` alias는 생성하지 않으므로, 같은 이름의 기존 전역 또는 중첩
payload 타입의 의미를 유지합니다. 고정 접두사 이름은 명시적 표기의 편의성과
교환한 선택이며 모든 이름 충돌을 방지한다는 뜻은 아닙니다. Compiler-owned
namespace에 사용자 이름을 만들지 마세요. 이 API는 미출시 7.0 후보에 포함되며,
공개 API baseline 검토와 지원 Apple toolchain 검증이 남아 있습니다.

## 비동기 shared 수명

`asyncFactory:`로 생성하는 `.shared` provider는 기본적으로 eager입니다. 컨테이너
initializer가 실행되는 동안, 어떤 읽기보다 먼저 비구조적 생성 task를 시작합니다.
읽기는 그 task 하나를 기다립니다. 컨테이너는 이 task를 취소하지 않습니다. 읽는
쪽을 취소해도 생성은 취소되지 않고, 컨테이너를 해제해도 이미 시작된 작업은
취소되지 않습니다.

`.transient` `@SubContainer`는 읽을 때마다 새 자식 컨테이너를 만들므로, 읽을
때마다 그 자식의 eager 비동기 `.shared` provider가 다시 시작됩니다.

첫 읽기에서 값을 만들려면 `initialization: .onDemand`를 추가하세요.

<!-- innodi:compile -->
```swift
import InnoDI

struct APIClient: Sendable {}

struct Session: Sendable {
    static func open(client: APIClient) async throws -> Session { Session() }
}

@DIContainer
struct AppContainer {
    @Input var client: APIClient

    @Provide(.shared, initialization: .onDemand, asyncFactory: { (client: APIClient) async throws in
        try await Session.open(client: client)
    })
    var session: Session
}

func run(_ container: AppContainer) async throws {
    let session = try await container.session
    _ = session
    await container.closeAsyncProviders()
}
```

- initializer는 아무것도 시작하지 않습니다. 첫 읽기가 생성 task 하나를 시작하고,
  동시에 들어온 읽기는 그 task를 기다립니다.
- 읽는 쪽을 취소하면 그 읽기의 대기만 취소됩니다. 생성은 다른 읽기를 위해
  계속됩니다.
- factory가 throw하지 않아도 accessor는 `get async throws`입니다.
- 값이나 실패는 eager provider와 마찬가지로 provider 수명 동안 캐시됩니다.
- override 값은 초기화 시점에 provider를 완료합니다. factory는 실행되지
  않습니다.
- 값 타입과 factory가 캡처하는 모든 의존성은 `Sendable`이어야 합니다.
  main-actor 컨테이너는 factory를 main actor에서 실행하므로 캡처도 main-actor
  규칙을 따릅니다.

비동기 on-demand provider가 하나라도 있는 컨테이너에는 `closeAsyncProviders()`도
생성됩니다. 닫으면 진행 중인 생성을 취소하고, 기다리던 모든 읽기를
``DIAsyncScopeError/closed(providerID:)``로 재개하고, 값을 놓아 주며, 이후
읽기도 같은 오류를 throw합니다. 아직 시작하지 않은 생성은 factory를 실행하지
않고, 이미 실행 중인 factory는 취소를 관찰하며 그래도 반환한 값은 버립니다.
override한 provider도 똑같이 닫히고 그 값을 놓아 주므로, override를 쓰는
테스트도 production과 같은 계약을 관찰합니다. provider ID는 member 이름입니다. 여러 번
닫아도 결과는 같습니다.
컨테이너 복사본은 provider를 공유하므로 어느 복사본을 닫아도 모든 복사본에서
닫힙니다. On-demand consumer를 그 on-demand 의존성보다 먼저 닫으며,
이 순서는 선언이나 초기화 순서와 독립적입니다.

기존 이름과 달리 `closeAsyncProviders()`는 비동기 on-demand provider만 닫습니다.
Eager task, transient factory, sub-container를 닫거나 전체 graph의 admission을
원자적으로 차단하지 않습니다. Eager와 on-demand shared 작업을 한 경계에서
닫아야 한다면 `makeOwned`의 생성된 owner를 사용하세요. Legacy close 중에도
실행 중인 eager consumer는 닫힌 on-demand 의존성을 관찰할 수 있습니다.

명시적 작업 우선순위 승격을 지원하는 런타임(Apple OS 26 이상)에서는 실행 중인
scope에 참여한 reader의 현재 작업 우선순위를 생성 작업에 전달합니다. 낮은
우선순위 reader가 기존 우선순위를 내리지는 않습니다. OS QoS 값이나 실행 지연,
이미 대기 중인 reader의 나중 우선순위 변경까지 전파한다고 보장하지 않습니다.
이전 Apple 런타임은 기존 작업 우선순위 동작을 유지합니다.

eager 비동기 consumer는 여전히 초기화 중에 시작하므로, 그 consumer가 의존하는
on-demand provider도 그때 생성됩니다.

읽을 때마다 새 값을 만들어야 한다면 `asyncFactory:`를 쓰는 `.transient`
provider를 선택하세요. 그 transient 사용 사례에 custom 수명 adapter가 필요하면
``DIAsyncScope``를 `@Input`으로 주입하세요. 지원되는 shared graph에는
`generateOwned: true`로 typed preparation, retry와 명시적 close를 추가할 수
있습니다. <doc:OwnedContainers>를 참고하세요.

## See Also

- ``Provide(_:_:with:initialization:effect:collection:factory:asyncFactory:)``
- ``DIScope``
- <doc:Validation>

### Prewarm 선택 마이그레이션

`try container.prewarm(\FeatureContainer.metrics)`를
`container.prewarm(.metrics)`로 바꾸고 빈 호출의 `try`를 제거합니다. Receiver와
컨테이너의 타입을 확인할 수 있는 단순 key path literal은 codemod로 바꿀 수
있지만, 임의의 `PartialKeyPath` 변수나 generic key path API는 자동 변환되지
않습니다. 해당 컨테이너의 생성된 token 타입을 저장하거나, 명시적인 warming
closure를 받도록 generic adapter를 바꿔야 합니다. 지원하지 않는 provider는
런타임 `DIPrewarmError` 대신 컴파일 단계에서 거부됩니다. Reflection 기반 변환이나
key path resolver fallback은 제공하지 않습니다.
`InnoDI-Migrate`는 prewarm 호출을 재작성하지 않으므로 직접 옮기세요.
`DIPrewarmError` 선언은 호환성을 위해 유지됩니다.
