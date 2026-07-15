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

## Matching Strategy

- `InnoDIMacros`, `InnoDICore`, graph CLI는 가능한 한 동일한 nominal-path 모델을 공유합니다.
- `Outer.Container` 같은 nested path를 지원합니다.
- generic argument extension과 constrained `where` extension은 제외합니다.
- 모호하거나 지원되지 않는 케이스는 추측해서 매치하지 않습니다.

## Declaration Order

- `.input` 멤버는 항상 사용 가능합니다.
- sync `.shared`는 input과 이전 sync shared를 참조할 수 있습니다.
- async `.shared`는 input, sync shared, 이전 async shared를 참조할 수 있습니다.
- `.transient`는 어떤 멤버도 참조할 수 있지만 이름 해석은 여전히 엄격합니다.

## Provider 효과

- 동기 provider는 sync, `async`, `async throws` factory에서 소비할 수 있습니다.
- `async` provider는 `async` 또는 `async throws` consumer가 필요합니다.
- `async throws` provider는 `async throws` consumer가 필요합니다.
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
- `@DIComponent`와 함께 사용하면 생성된 dependency protocol,
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
- `Lazy<T>`와 `Provider<T>` wrapper는 actor 사이의 전송 수단이 아닙니다. `T`와
  주변 호출 경로를 옮겨도 안전한 경우가 아니라면 컨테이너의 격리 domain 안에
  머무르는 것으로 취급하세요.
- non-`Sendable` 의존성은 global lookup 뒤에 숨기지 말고 명시적인 컨테이너
  경계를 통해 전달하고 앱 레이어에서 격리하세요.

## 선언 타입이 결정하는 Storage Shape

- protocol-first dependency 설계를 권장합니다.
- 선언된 property type이 source of truth입니다. Concrete nominal type은
  concrete storage를, `any Protocol`은 existential storage를 사용합니다.
- Storage shape은 attribute flag나 macro heuristic으로 선택하지 않습니다.
