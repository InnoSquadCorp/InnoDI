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

사용자가 nested `Overrides` 타입을 이미 선언하지 않은 한, 지원되는 모든
컨테이너가 overrides scaffolding을 생성합니다.

## 파라미터

- `root`: 그래프 렌더 엔트리 플래그입니다. root가 하나라도 있으면
  Mermaid, DOT, ASCII 출력은 root에서 도달 가능한 노드와 엣지 union으로
  잘립니다.
- `validateDAG`: global DAG validation과 매크로의 local cycle 및
  closure/`with:` graph-derived 진단을 켭니다. `false`면 그 범위만
  건너뛰고 raw-expression `factory:`와 initializer reference, 구조
  진단은 계속 남습니다.
- `mainActor`: 생성된 컨테이너 API에 `@MainActor` 격리를 적용합니다.

## See Also

- <doc:Validation>
- <doc:Provide>
