# Module-Wide Init Detection

`@DIContainer`는 매크로와 build validation 두 레이어에서 custom `init`
제한을 적용합니다.

## Macro Layer

매크로 검증은 annotated type body 안의 custom `init`만 거부합니다. attached
macro는 같은 소스 파일의 sibling extension을 안정적으로 확인할 수 없습니다.

## 필수 Build Layer

컨테이너를 선언하는 모든 target에 `InnoDIDAGValidationPlugin`을 연결해야 합니다.
이 plugin의 full-source preflight는 semantic validation과 DAG validation 전에
같은 파일과 다른 파일의 일치하는 extension에 선언된 `init`을 모두 거부하며,
`#if` branch 안의 선언도 포함합니다.

build-validation plugin을 적용하지 않으면 모든 extension에 대한 custom `init`
금지 계약은 보장되지 않습니다.

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
