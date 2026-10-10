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
- `@Provide`의 직접적이고 평범한 stored instance `var` 배치
- missing factory
- declaration-order availability
- local dependency cycle
- strict name-based resolution
- 명시적 sibling edge의 효과 호환성
- invalid user-defined `init`
- async factory validity

명시적 sibling edge는 root `factory:`/`asyncFactory:` 클로저 리터럴의 이름 있는
파라미터 또는 `Type.self`와 literal `with:` key path에서만 만들어집니다. 클로저가
아닌 factory와 property initializer는 opaque한 zero-edge source이며 sibling
member를 참조할 수 없습니다.

`validateDAG: false`는 선언 검증이나 명시적 edge의 효과 호환성 검증을 끄지
않습니다. global DAG와 로컬 graph-derived 가용성 검사만 건너뜁니다. 로컬
소유권 순환은 항상 거부됩니다. `Lazy`나 `Provider`를 통하는 순환도 예외가
아닙니다.

## Build Validation

coordinated build pipeline은 다음을 추가합니다.

1. cross-file custom `init` validation
2. semantic container reference check
3. component/root `@DIContainerRole` hierarchy validation
4. DAG validation
5. metrics / summary artifact emission

빌드 plugin의 소스 manifest는 package 내부 디렉터리의 symlink를 포함해
선언된 소스의 package-relative 경로를 유지합니다. symlink는 해당 package
내부로 해석되어야 하며, 서로 다른 선언 경로가 같은 실제 파일을 소유할 수는
없습니다. package 외부로 향하는 symlink는 declared source로 지원하지
않습니다.

## Global DAG Validation

Global graph 검증에는 CLI를 사용하세요.

```bash
swift run InnoDI-DependencyGraph --root . --validate-dag
```

`validateDAG: false` 컨테이너는 global DAG validation에서 제외되지만, 지원하지
않는 provider 선언과 명시적 sibling edge의 효과 불일치는 여전히 compile-time
진단 대상입니다.

## Artifacts

build validation은 다음 산출물을 생성합니다.

- `validation-metrics.json`
- `validation-summary.md`
- `dag-validation-metrics.json`
- `dag-validation-summary.md`

이 산출물은 `RELEASING.md`에 문서화된 릴리즈 계약의 일부입니다.
산출물은 plugin work directory와 그 안의 validation-state 디렉터리에 남으며,
plugin이 target resource로 선언하지 않습니다. Swift target은 컴파일 전에
검증이 실행되도록 주석만 있는 generated Swift 파일만 output으로 선언합니다.
SwiftPM Clang target에는 Swift 소스가 추가되지 않도록 output 없는 command를
사용합니다. SwiftPM에서 output 없는 command를 실행하려면 tools version
6.0 이상이 필요합니다.

미배포 native Xcode adapter는 plugin work directory 안에서 configuration,
effective platform, SDK platform별로 output을 분리합니다. output 누락 경고와
iOS/watchOS 출력 충돌을 해결하며, Swift target에는 주석만 있는 Swift input을,
Clang target에는 주석만 있는 header를 선언합니다. 변경 없는 빌드에서도 Xcode가
gate를 실행할 수 있지만, coordinator는 검증 캐시를 재사용하고 내용이 같은
generated input의 timestamp를 보존합니다. 소스나 manifest가 바뀌면 검증이
무효화됩니다. 배포된 7.0.1 Xcode adapter는 output 없는 gate를 사용합니다.

plugin은 문서화된 coordinator 환경 변수만 전달합니다.
`INNODI_LOCK_TIMEOUT`, `INNODI_STALE_LOCK_AGE`, `INNODI_ALLOW_UNSAFE_LOCK`,
`INNODI_VALIDATION_VERBOSE`, `INNODI_VALIDATION_DEBUG`를 빌드를 시작하는
환경에 설정하세요. 값 검증과 기본값은 coordinator가 그대로 처리하며, 운영자의
명시적 opt-in이 없으면 안전하지 않은 파일시스템을 거부합니다.
자세한 내용은 <doc:lock-safety>를 참고하세요.

## See Also

- <doc:DIContainer>
- <doc:Provide>
- <doc:PolicyBoundaries>
- <doc:ModuleWideInitDetection>
