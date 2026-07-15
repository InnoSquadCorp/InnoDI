# DIContainer

`@DIContainer`는 지원되는 유효한 non-generic struct를 InnoDI 컨테이너로
표시하고 컨테이너 API를 합성합니다.

`@DIContainer`가 지원하는 선언은 file scope 또는 nominal type 안에 nested된,
유효하게 non-generic인 `struct`뿐입니다. 선언 자체와 모든 enclosing 선언에
generic parameter나 `where` clause가 없어야 합니다. `class`, `actor`, `enum`,
`protocol`, 직접 annotated된 `extension`, extension 안에 nested된 struct는
거부됩니다. 함수, closure, accessor, `switch` case를 포함한 executable/local
code scope 안의 선언도 거부됩니다. 이 경계는 `@DIComponent`를 함께 적용한
선언에도 동일합니다. runtime 또는 타입별 state는 protocol dependency나
`@Provide(.input)` 뒤로 옮기세요.

명시적으로 `private`인 컨테이너도 sibling container가 생성된 mount surface에
접근할 수 없어 거부됩니다. 같은 파일에서 mount하려면 `fileprivate`를 사용하거나,
private namespace 안에 default-access container를 중첩하세요.

현재 Swift compiler는 computed-property body 안 타입의 attached macro를
확장할 때 accessor ancestry를 macro context에서 누락합니다. 이 edge case는
build-validation plugin과 dependency-graph CLI가 전체 source tree를 scan해
거부합니다. 컨테이너를 선언하는 모든 target에 plugin을 연결하세요.

## 선언

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

## 생성 표면

`@DIContainer`는 다음을 합성합니다.

- primary `init(...)`
- nested `Overrides` 타입
- convenience `init(<inputs...>, _ applyOverrides: ...)`
- 네 가지 `withOverrides` effect overload

`mainActor: true`를 사용하지 않는 컨테이너에서는 생성되는 `async`와
`async throws` `withOverrides` 메서드 및 operation closure 타입이
`nonisolated(nonsending)`입니다. 호출자 actor executor를 유지하므로 임의의
non-`Sendable` container와 closure 값이 isolation 경계를 넘지 않습니다. 동기
overload는 바뀌지 않습니다. `mainActor: true`에서는 모든 `withOverrides` overload와
operation closure가 계속 `@MainActor`입니다.

관리 멤버가 없는 경우까지 지원되는 모든 컨테이너가 전체 overrides scaffolding을
생성합니다. 사용자가 nested `Overrides` 타입을 직접 선언하는 것은 InnoDI 5.0에서
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

## 파라미터

- `root`: 그래프 렌더 엔트리 플래그입니다. root가 하나라도 있으면
  Mermaid, DOT, ASCII 출력은 root에서 도달 가능한 노드와 엣지 union으로
  잘립니다.
- `validateDAG`: global DAG validation과 local graph-derived 진단을 켭니다.
  `false`면 global DAG와 local cycle 진단은 건너뛰지만 선언 검증과 명시적
  sibling edge의 효과 호환성 검증은 계속 동작합니다.
- `mainActor`: 의존성 accessor, 모든 생성 initializer, `Overrides`, convenience
  initializer·`withOverrides`·child override·component mount에 쓰이는
  `applyOverrides` 함수 타입, 네 가지 `withOverrides` operation closure,
  feature-root helper에 `@MainActor` 격리를 적용합니다. `@DIComponent`와 함께
  사용하면 생성된 `<Container>Dependencies` protocol과
  `init(dependencies:_:)`도 같은 격리를 받고, component는 전용
  `_InnoDIMainActorComponentMountable` protocol에 conform합니다. 옵션을 쓰지
  않는 일반 component는 `_InnoDIComponentMountable`을 계속 사용합니다.
  non-`Sendable` 생성 값은 `@MainActor` caller를 사용하거나 `MainActor.run` 안에서
  생성하고 소비해 main actor에 유지하세요. direct `await`는 격리된 작업이
  `Sendable` 결과를 반환할 때 적합하며, container 자체를 actor 밖으로 옮기는
  용도가 아닙니다.

## See Also

- <doc:Validation>
- <doc:Provide>
