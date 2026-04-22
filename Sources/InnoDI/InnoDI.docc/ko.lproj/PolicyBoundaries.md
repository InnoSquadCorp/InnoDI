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

## Concrete Opt-In

- protocol-first dependency 설계를 권장합니다.
- concrete `.shared` / `.transient` 저장은 `concrete: true`가 필요합니다.
