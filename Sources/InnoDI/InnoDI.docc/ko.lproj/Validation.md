# Validation

InnoDI는 의존성 정의를 여러 단계에서 검증합니다.

## Read This Next

권장 읽기 순서:

1. `README.ko.md`
2. 이 문서
3. <doc:PolicyBoundaries>
4. <doc:ModuleWideInitDetection>

## Macro Validation

매크로 검증은 다음을 확인합니다.

- 스코프 규칙
- missing factory
- declaration-order availability
- local dependency cycle
- strict name-based resolution
- invalid user-defined `init`
- async factory validity

`validateDAG: false`는 구조 검증을 끄지 않습니다. 매크로의 local cycle 및
closure/`with:` graph-derived 진단만 건너뜁니다.

## Build Validation

coordinated build pipeline은 다음을 추가합니다.

1. cross-file custom `init` validation
2. semantic container reference check
3. `@DIComponent` / `@DIHierarchyRoot` hierarchy validation
4. DAG validation
5. metrics / summary artifact emission

## Global DAG Validation

```bash
swift run InnoDI-DependencyGraph --root . --validate-dag
```

`validateDAG: false` 컨테이너는 global DAG validation에서 제외되지만,
raw-expression `factory:`와 initializer reference는 여전히 compile-time
진단 대상입니다.

## Artifacts

build validation은 다음 산출물을 생성합니다.

- `validation-metrics.json`
- `validation-summary.md`
- `dag-validation-metrics.json`
- `dag-validation-summary.md`

이 산출물은 `RELEASING.md`에 문서화된 릴리즈 계약의 일부입니다.
