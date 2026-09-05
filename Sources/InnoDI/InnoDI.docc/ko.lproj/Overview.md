# ``InnoDI``

계층형 검증을 제공하는 매크로 기반 Swift DI 프레임워크입니다.

## 개요

InnoDI는 `@DIContainer`와 `@Provide`를 통해 file scope 또는 nominal type 안에
nested된, 지원되는 유효한 non-generic Swift struct를 DI 컨테이너로 바꿉니다.
함수, closure, accessor, `switch` case를 포함한 executable/local code scope
안의 선언은 지원하지 않습니다. 런타임 변형보다 명시적 wiring, 결정적 검증,
graph tooling에 초점을 둡니다.

4.0.0의 stable baseline:

- 매크로 기반 컨테이너 API 생성
- 컴파일 타임과 빌드 타임 검증
- global dependency graph 렌더링과 DAG 검증
- `Lazy<T>`와 `Provider<T>` deferred edge
- `@SubContainer`, `@DIComponent`, `@DIHierarchyRoot`
- `InnoDISwiftUI`의 SwiftUI helper

4.1.0은 이 baseline 위에 release hardening을 추가합니다.

- validation coordinator lock의 unsafe filesystem fail-fast
- 지원 파일시스템에서 `O_CREAT | O_EXCL`와 `flock`을 함께 쓰는 layered lock
- macro-synthesized `fatalError` accessor 대신 build-time diagnostic
- strict concurrency와 macro-source `fatalError` allow-list를 모두 강제하는 PR/release gate
- `@SubContainer` same-name wiring은 `with:`만 사용하며 `withNames:` escape hatch는 제거됨

## Topics

### Tutorials

- <doc:GettingStarted>
- <doc:Tutorial-01-Hello>
- <doc:Tutorial-02-Inputs>
- <doc:Tutorial-03-Wiring>
- <doc:Tutorial-04-Concrete>
- <doc:Tutorial-05-SubContainer>

### Start Here

- <doc:Validation>
- <doc:PolicyBoundaries>
- <doc:AntiPatterns>
- <doc:IntegrationGuide>
- <doc:ModuleWideInitDetection>
- <doc:DiagnosticsGuide>

### Operations

- <doc:lock-safety>
- <doc:AsyncPreparation>
- <doc:MigrationGuide>

### Container API

- <doc:DIContainer>
- <doc:Provide>
- ``DIComponent()``
- ``DIHierarchyRoot()``

### Symbols

- ``DIContainer(root:validateDAG:mainActor:)``
- ``Provide(_:_:with:factory:asyncFactory:escaping:)``
- ``DIScope``
- ``Lazy``
- ``Provider``
- ``DIAsyncScope``
- ``DIAsyncPreparationPlan``
