# DIContainer

`@DIContainer`는 타입을 InnoDI 컨테이너로 표시하고 컨테이너 API를 합성합니다.

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

사용자가 nested `Overrides` 타입을 이미 선언하지 않은 한, 모든 컨테이너가
overrides scaffolding을 생성합니다.

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
