# Policy Boundaries

InnoDI는 몇 가지 명시적 경계를 두어 검증을 결정적으로 유지합니다.

## Custom `init` Detection

- 매크로 검증은 annotated type의 custom `init`을 거부합니다.
- 같은 타입 경로를 가리키는 same-file extension의 `init`도 거부합니다.
- build validation은 같은 규칙을 cross-file extension까지 확장합니다.

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

## Concrete Opt-In

- protocol-first dependency 설계를 권장합니다.
- concrete `.shared` / `.transient` 저장은 `concrete: true`가 필요합니다.
