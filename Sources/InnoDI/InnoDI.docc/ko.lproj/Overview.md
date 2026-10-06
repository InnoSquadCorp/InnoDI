# ``InnoDI``

계층형 검증을 제공하는 매크로 기반 Swift DI 프레임워크입니다.

## 개요

InnoDI는 `@DIContainer`와 `@Provide`를 통해 file scope 또는 nominal type 안에
nested된, 지원되는 유효한 non-generic Swift struct를 DI 컨테이너로 바꿉니다.
함수, closure, accessor, `switch` case를 포함한 executable/local code scope
안의 선언은 지원하지 않습니다. 런타임 변형보다 명시적 wiring, 결정적 검증,
graph tooling에 초점을 둡니다.

최신 안정 릴리스는 7.0.0입니다. 이 소스 문서는 7.0 API를 설명합니다.
안정 버전을 설치했다면 해당 tag의 문서를 사용하세요. 패키지는 다음을 제공합니다:

- 매크로 기반 컨테이너 API 생성
- 컴파일 타임과 빌드 타임 검증
- global dependency graph 렌더링과 DAG 검증
- `Lazy<T>`와 `Provider<T>` deferred edge
- `@SubContainer`, 명시적 `@DIContainerRole` hierarchy role
- `InnoDISwiftUI`의 SwiftUI helper

InnoDI 7.0은 명시적인 소유권과 소비자 계약을 추가합니다:

- `generateOwned: true`, 선택한 async 준비·취소·재시도·종료
- 선택한 준비 상태를 확인하고 정리를 기다리는 `withPrepared`
- typed prewarm 선택과 선택적인 dependency 초기화 순서
- 명시적 optional nil/default override 변경과 effect preset 검증
- 컴파일러가 검사하는 deferred capture와 명시적인 feature-host import

생성과 접근은 계속 매크로가 만드는 typed Swift입니다. Owned lifecycle 지원은
concrete scope를 조율하며 문자열로 서비스를 찾지 않습니다. Breaking change는
<doc:MigrationGuide>, 소유권 경계는 <doc:OwnedContainers>를 참고하세요.
Portable 테스트 일부의 통과가 지원 Apple toolchain과 release 검증을 대체하지는 않습니다.

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

### 다른 라이브러리에서 옮기기

- <doc:MigratingFromFactory>
- <doc:MigratingFromSwinject>

### Operations

- <doc:lock-safety>
- <doc:DAGValidation>
- <doc:AsyncPreparation>
- <doc:OwnedContainers>
- <doc:RuntimeTracing>
- <doc:PluginOptOut>
- <doc:MigrationGuide>

### Container API

- <doc:DIContainer>
- <doc:Provide>
- ``Input(_:escaping:)``
- ``DIContainerRole(role:mainActor:validateDAG:initializationOrder:generateOwned:)``

### Experimental

- <doc:AutoMock>

### SwiftUI Preview Helper

- <doc:SwiftUIPreviewHelper>

### Symbols

- ``DIContainer(validateDAG:initializationOrder:generateOwned:)``
- ``Provide(_:_:with:initialization:effect:collection:factory:asyncFactory:)``
- ``DIScope``
- ``Lazy``
- ``Provider``
- ``DIAsyncScope``
- ``DIAsyncPreparationPlan``
