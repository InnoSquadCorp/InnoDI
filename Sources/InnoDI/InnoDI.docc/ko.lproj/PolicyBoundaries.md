# Policy Boundaries

InnoDI는 몇 가지 명시적 경계를 두어 검증을 결정적으로 유지합니다.

## Custom `init` Detection

- 매크로 검증은 annotated type body 안의 custom `init`만 거부합니다.
- 필수 `InnoDIDAGValidationPlugin` full-source preflight는 같은 파일과 다른 파일의
  일치하는 extension에 선언된 `init`을 모두 거부하며, `#if` branch 안의 선언도
  포함합니다.
- build-validation plugin을 적용하지 않으면 attached macro가 sibling extension을
  안정적으로 확인할 수 없으므로 extension 전체에 대한 금지 계약은 보장되지
  않습니다.

## Generated Qualifier와 Bridge 경계

- InnoDI container 또는 standalone `@DIEnvironmentBridge`를 선언하는 모든 target에
  `InnoDIDAGValidationPlugin`을 붙입니다.
- target-scoped full-source pass는 attached macro가 검사할 수 없는 enclosing
  declaration, matching extension, 같은 target의 다른 source에 있는 generated
  qualifier shadow와 현재 target에서 보이는 imported dependency target의 `public`
  또는 `package` qualifier shadow를 거부합니다.
- `@DIEnvironmentBridge`를 extension에 직접 붙이거나 standalone local scope에
  선언하는 형태도 거부합니다. Bridge target을 file 또는 nominal scope로
  옮기세요.
- Class bridge 또는 class 안에 중첩된 generated site의 첫 inherited type은
  source-visible declaration과 typealias를 통해 해소되어야 합니다. 이 pass는
  Swift의 semantic type checker가 아닌 보수적인 syntactic index이므로 SDK나
  binary에만 있거나 해소되지 않거나 모호한 첫 inherited type은
  `generated-qualifier.inheritance-unverifiable`로 fail closed합니다.
- Source-visible superclass chain에서 qualifier shadow를 검사합니다. Bridge
  생성은 상속된 type member `Swift`와 `SwiftUI`를 거부하지만 상속된
  `InnoDISwiftUI`는 안전합니다. 직접 또는 enclosing scope의
  `InnoDISwiftUI` declaration은 계속 예약됩니다.

## Matching Strategy

- `InnoDIMacros`, `InnoDICore`, `InnoDI-DependencyGraph`는 같은 경량
  nominal-path 모델과 서로 맞춘 parser/graph semantics를 공유하며 이를
  보장합니다.
- `Outer.Container` 같은 nested path를 지원합니다.
- generic argument extension과 constrained `where` extension은 제외합니다.
- 모호하거나 지원되지 않는 케이스는 추측해서 매치하지 않습니다.

## Declaration Order

- `@Input` 멤버는 항상 사용 가능합니다.
- sync `.shared`는 input과 이전 sync shared를 참조할 수 있습니다.
- async `.shared`는 input, sync shared, 이전 async shared를 참조할 수 있습니다.
- `.transient`는 어떤 멤버도 참조할 수 있지만 이름 해석은 여전히 엄격합니다.

위 규칙은 기본값 `ContainerInitializationOrder.declaration`의 계약입니다.
`ContainerInitializationOrder.dependency`는 sync-shared 및 async-shared 단계
각각에서 안정적인 위상 순서로 생성하는 opt-in입니다. 같은 단계의 hard forward
reference를 허용하며, async 단계는 입력과 모든 sync-shared 값에 접근합니다.
scope/effect 제한과 ownership-cycle 검사는 유지하고 deferred edge는 생성 순서를
정하지 않습니다. factory 부수효과의 순서가 바뀔 수 있으므로 도입 전에
<doc:DIContainer>를 확인하세요.

## Provider 효과

- 동기 provider는 sync, `async`, `async throws` factory에서 소비할 수 있습니다.
- `async` provider는 `async` 또는 `async throws` consumer가 필요합니다.
- `async throws` provider는 `async throws` consumer가 필요합니다.
- 비동기 `.onDemand` provider는 factory가 throw하지 않아도 `async throws`
  consumer가 필요합니다. 읽기가 읽는 쪽의 취소나 닫힌 provider를 관찰할 수
  있기 때문입니다.
- 효과는 의존성에서 추론하지 않습니다. Consumer가 `asyncFactory:`와, 필요한
  경우 `async throws` 클로저를 명시해야 합니다.
- `Lazy<T>`와 `Provider<T>`는 동기 deferred wrapper이며 async target을
  거부합니다.

## 격리와 Sendability

- 컨테이너는 생성된 storage를 컨테이너 값 내부에 유지합니다. InnoDI는
  의존성을 global registry에 설치하지 않습니다.
- `mainActor: true`는 의존성 accessor, 모든 생성 initializer, `Overrides`,
  convenience initializer·`withOverrides`·child override·component mount에
  쓰이는 `applyOverrides` 함수 타입, 네 가지 `withOverrides` operation closure,
  생성된 feature-root helper를 격리합니다. UI 루트 컨테이너에 권장되는
  형태입니다.
- component 역할의 `@DIContainerRole`을 사용하면 생성된 dependency protocol,
  `init(dependencies:_:)`, override 적용 closure 타입이 `@MainActor`로 격리되고,
  component는 전용 `_InnoDIMainActorComponentMountable` protocol에 conform합니다.
  일반 component는 비격리 `_InnoDIComponentMountable` protocol을 계속 사용합니다.
  5.0의 generic mounting helper는 두 marker별 constraint와 closure 타입을 따로
  제공해야 합니다.
- 생성된 container/component 값과 non-`Sendable` dependency는 main actor 안에
  유지하세요. `@MainActor` caller를 사용하거나, `MainActor.run` block 안에서
  값을 생성하고 소비하는 방식을 권장합니다. direct `await`는 `withOverrides`
  operation result처럼 격리된 작업이 `Sendable` 결과를 반환할 때 적합합니다.
  non-`Sendable` container를 actor 밖으로 가져와도 안전하게 만들지는 않습니다.
- `Lazy<T>`, `Provider<T>`와 생성된 deferred cell은 non-`Sendable`입니다.
  생성된 비동기 작업이 격리 경계를 넘으면 Swift가 payload와 resolver capture를
  검사합니다. 결과가 `Sendable`이어도 capture한 non-`Sendable` 의존성이 안전해지는
  것은 아니며, 동기 on-demand factory를 통한 간접 capture에도 같은 규칙이
  적용됩니다. 이런 그래프는 하나의 actor에 유지하거나 전체 capture 경로가
  컴파일러 검사를 통과하는 의존성을 사용하세요. 생성된 eager task는 deferred
  target의 binding이 모두 끝난 뒤 시작합니다.
- 컨테이너에 명시한 `@MainActor`도 `mainActor: true` 옵션과 동일하게 생성된
  on-demand factory capture의 격리를 유지합니다.
- non-`Sendable` 의존성은 global lookup 뒤에 숨기지 말고 명시적인 컨테이너
  경계를 통해 전달하고 앱 레이어에서 격리하세요.

## DAG Opt-Out

- `validateDAG: false`는 해당 컨테이너의 global DAG 검증과 로컬
  graph-derived 가용성 검사를 끕니다. 로컬 소유권 순환은 항상 거부되며
  `Lazy`나 `Provider`를 통하는 순환도 예외가 아닙니다.
- 구조 검증은 계속 실행됩니다. 지원하지 않는 custom `init` 선언, 잘못된
  `@SubContainer` binding, 형식이 잘못된 deferred wrapper와 그 밖의 로컬
  매크로 규칙은 여전히 진단됩니다.
- Opt-out은 legacy module, 임시 마이그레이션 단계, 실제 lifetime을 다른
  시스템이 검증하는 컨테이너처럼 의도한 integration 경계에만 사용하세요.

## Deferred Wrapper의 한계

- `Lazy<T>`와 `Provider<T>`는 생성을 지연하지만 소유권 순환을 끊지는
  않습니다. 로컬 소유권 검증과 global DAG 검증은 모두 deferred edge를
  포함합니다. 순환 wiring이 아니라 on-demand 해소와 비순환 forward
  reference에 사용하세요.
- 지연은 factory가 wrapper를 받아 저장하거나 전달할 때만 효과가 있습니다.
  Factory가 의존성을 생성하는 도중 wrapper를 바로 호출하면 그 의존성은
  사실상 다시 eager가 됩니다. InnoDI는 `.shared` 생성 안에서 `lazy()` /
  `provider()`를 직접 호출하는 표기와 `callAsFunction()` / `resolver()`로
  직접 호출하는 표기를 진단합니다.
- Helper function을 거친 간접 eager 호출은 InnoDI가 검사하지 않습니다.
  지연 생성이 유지되도록 해당 factory를 직접 검토하세요. 순환을 wrapper
  뒤에 숨기려 하지 말고 소유권을 재구성해 순환을 제거하세요.

<!-- innodi:compile -->
```swift
import InnoDI

struct Config {}
struct Service { init(config: Config) {} }
struct Request { init(config: Config) {} }
struct Consumer {
    let service: Lazy<Service>
    let requests: Provider<Request>
}

@DIContainer
struct AppContainer {
    @Input
    var config: Config

    @Provide(.shared, factory: { (config: Config) in
        Service(config: config)
    })
    var service: Service

    @Provide(.transient, factory: { (config: Config) in
        Request(config: config)
    })
    var request: Request

    @Provide(.shared, factory: { (service: Lazy<Service>, request: Provider<Request>) in
        Consumer(service: service, requests: request)
    })
    var consumer: Consumer
}

let container = AppContainer(config: Config())
_ = container.consumer
```

<!-- innodi:compile -->
```swift
import InnoDI

struct Config {}
struct FeatureService { init(config: Config) {} }

@DIContainer
struct FeatureContainer {
    @Input
    var featureConfig: Config

    @Provide(.shared, factory: { (featureConfig: Config) in
        FeatureService(config: featureConfig)
    })
    var service: FeatureService
}

@DIContainer
struct AppContainer {
    @Input
    var config: Config

    @SubContainer(
        scope: .shared,
        bindings: [(child: \FeatureContainer.featureConfig, parent: \Self.config)]
    )
    var feature: FeatureContainer
}

let container = AppContainer(config: Config())
_ = container.feature
```

## 선언 타입이 결정하는 Storage Shape

- protocol-first dependency 설계를 권장합니다.
- 선언된 property type이 source of truth입니다. Concrete nominal type은
  concrete storage를, `any Protocol`은 existential storage를 사용합니다.
- Storage shape은 attribute flag나 macro heuristic으로 선택하지 않습니다.

## Runtime Lookup 트레이드오프

- InnoDI에는 의도적으로 `@Injected` property wrapper가 없습니다.
- InnoDI에는 의도적으로 dynamic registration API가 없습니다.
- Late registration이나 plugin-style composition이 주된 요구라면 runtime
  DI 도구를 사용하세요. 생성된 initializer, 명시적 override, 결정적 검증이
  주된 요구라면 InnoDI를 사용하세요.

## See Also

- <doc:Validation>
- <doc:IntegrationGuide>
- <doc:ModuleWideInitDetection>
