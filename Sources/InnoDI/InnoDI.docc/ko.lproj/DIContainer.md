# DIContainer

`@DIContainer`는 지원되는 유효한 non-generic struct를 InnoDI 컨테이너로
표시하고 컨테이너 API를 합성합니다.

`@DIContainer`가 지원하는 선언은 file scope 또는 nominal type 안에 nested된,
유효하게 non-generic인 `struct`뿐입니다. 선언 자체와 모든 enclosing 선언에
generic parameter나 `where` clause가 없어야 합니다. `class`, `actor`, `enum`,
`protocol`, 직접 annotated된 `extension`, extension 안에 nested된 struct는
거부됩니다. 함수, closure, accessor, `switch` case를 포함한 executable/local
code scope 안의 선언도 거부됩니다. 이 경계는 component 역할의 `@DIContainerRole`을 적용한
선언에도 동일합니다. runtime 또는 타입별 state는 protocol dependency나
`@Input` 뒤로 옮기세요.

명시적으로 `private`인 컨테이너도 sibling container가 생성된 mount surface에
접근할 수 없어 거부됩니다. 같은 파일에서 mount하려면 `fileprivate`를 사용하거나,
private namespace 안에 default-access container를 중첩하세요.

현재 Swift compiler는 computed-property body 안 타입의 attached macro를
확장할 때 accessor ancestry를 macro context에서 누락합니다. 이 edge case는
build-validation plugin과 dependency-graph CLI가 전체 source tree를 scan해
거부합니다. 컨테이너를 선언하는 모든 target에 plugin을 연결하세요.

## 선언

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

## 생성 표면

`@DIContainer`는 다음을 합성합니다.

- primary `init(...)`
- nested `Overrides` 타입
- convenience `init(<inputs...>, _ applyOverrides: ...)`
- 네 가지 `withOverrides` effect overload

명시적 `@MainActor`와 `mainActor: true`를 모두 사용하지 않는 컨테이너에서는 생성되는 `async`와
`async throws` `withOverrides` 메서드 및 operation closure 타입이
`nonisolated(nonsending)`입니다. 호출자 actor executor를 유지하므로 임의의
non-`Sendable` container와 closure 값이 isolation 경계를 넘지 않습니다. 동기
overload는 바뀌지 않습니다. 명시적 `@MainActor` 또는 `mainActor: true`에서는 모든
`withOverrides` overload와 operation closure가 계속 MainActor에 격리됩니다.

관리 멤버가 없는 경우까지 지원되는 모든 컨테이너가 전체 overrides scaffolding을
생성합니다. 사용자가 nested `Overrides` 타입을 직접 선언하는 것은 InnoDI 6.0에서
지원하지 않으며 `container.overrides-name-conflict` 오류가 발생합니다. mount 가능한
override ABI는 매크로가 소유하도록 사용자 선언의 이름을 바꾸세요.

매크로는 부모 컨테이너의 mount 코드를 위해 compiler support 전용 별칭
`_InnoDIMountOverrides = Overrides`도 생성합니다. 이 underscore 이름을 직접
선언하거나 참조하지 마세요.

모든 stored instance member에는 `@Provide` 또는 `@SubContainer`가 필요합니다.
computed/type property는 계속 사용할 수 있습니다. 그래야 합성 initializer가 모든
stored state를 소유하고 memberwise initializer ABI 변화를 막을 수 있습니다.

각 `@Provide`는 이 struct의 직접적이고 평범한 stored instance `var`여야 합니다.
Accessor/observer, `let`, `lazy`, `weak`, `unowned`, `static`/`class`, standalone,
간접 nested provider는 거부되며 생성 accessor를 수동으로 붙일 수도 없습니다.

Sibling edge는 root `factory:`/`asyncFactory:` 클로저 리터럴의 이름 있는 파라미터
또는 `Type.self`와 literal `with:` key path에서만 만들어집니다. 클로저가 아닌
factory와 property initializer는 opaque한 zero-edge source이며 sibling member를
참조할 수 없습니다. 효과 호환성은 `validateDAG: false`에서도 필수입니다.

## 기본 격리가 MainActor인 타깃

문법 매크로에는 타깃의 암묵적인 기본 actor 설정이 전달되지 않습니다.
`.defaultIsolation(MainActor.self)` 또는 대응 compiler flag를 사용한다면
컨테이너에 격리를 명시하세요. `@MainActor @DIContainer`,
`@DIContainerRole(role: ContainerRole.local, mainActor: true)`, 또는 호출자 격리를
따르는 `@DIContainer nonisolated struct Services`를 사용합니다.
`generateOwned: true`와 async `withOverrides`에도 같은 경계가 적용됩니다.

컨테이너를 암묵적인 MainActor로 남겨두면 생성된 nonisolated async helper가
격리된 initializer를 호출해 compiler가 거부합니다. Provider 프로퍼티의
`nonisolated(nonsending)`만으로 이 생성 경계를 고칠 수는 없습니다.
현재 지원하는 방법은 명시적인 actor 선언이며, 빌드 설정을 자동 감지하는 것은 아닙니다.

## 파라미터

- `role`: `@DIContainerRole`에서 필수입니다. `ContainerRole.local`은 local 경계,
  `.component`는 모듈 간 mount 계약, `.root`는 계층 및 그래프 reachability 진입점입니다.
- `validateDAG`: global DAG validation과 local graph-derived 진단을 켭니다.
  `false`면 global DAG와 local availability 진단은 건너뛰지만 local ownership-cycle 검사, 선언 검증과 명시적
  sibling edge의 효과 호환성 검증은 계속 동작합니다.
- `mainActor`: 의존성 accessor, 모든 생성 initializer, `Overrides`, convenience
  initializer·`withOverrides`·child override·component mount에 쓰이는
  `applyOverrides` 함수 타입, 네 가지 `withOverrides` operation closure,
  feature-root helper에 `@MainActor` 격리를 적용합니다. component 역할과 함께
  사용하면 생성된 `<Container>Dependencies` protocol과
  `init(dependencies:_:)`도 같은 격리를 받고, component는 전용
  `_InnoDIMainActorComponentMountable` protocol에 conform합니다. 옵션을 쓰지
  않는 일반 component는 `_InnoDIComponentMountable`을 계속 사용합니다.
  non-`Sendable` 생성 값은 `@MainActor` caller를 사용하거나 `MainActor.run` 안에서
  생성하고 소비해 main actor에 유지하세요. direct `await`는 격리된 작업이
  `Sendable` 결과를 반환할 때 적합하며, container 자체를 actor 밖으로 옮기는
  용도가 아닙니다.

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
이 API는 미출시 7.0 후보에 포함되며, 공개 API baseline 검토와 지원 Apple
toolchain 검증이 남아 있습니다.

## See Also

- <doc:Validation>
- <doc:Provide>
