# Module-Wide Init Detection

`@DIContainer`는 매크로와 build validation 두 레이어에서 custom `init`
제한을 적용합니다.

## Macro Layer

매크로 검증은 다음 위치의 custom `init`을 거부합니다.

- annotated type body
- 같은 타입 경로를 가리키는 same-file extension

## Build Layer

build validation은 semantic validation과 DAG validation 전에 같은 규칙을
cross-file extension까지 확장합니다.

매칭 대상:

- normalized nominal path 기준의 `@DIContainer`
- normalized extended type path 기준의 extension `init`

## Boundaries

- nested path는 지원합니다.
- generic argument extension은 제외합니다.
- constrained `where` extension은 제외합니다.
- 모호하거나 지원되지 않는 케이스는 deterministic rule 밖에 둡니다.

이 단계의 structured failure는 <doc:Validation>에 설명된 동일한 validation
artifact pipeline으로 방출됩니다.
