# ``InnoDI``

계층형 검증을 제공하는 매크로 기반 Swift DI 프레임워크입니다.

## 개요

InnoDI는 `@DIContainer`와 `@Provide`를 통해 일반 Swift 타입을 DI
컨테이너로 바꿉니다. 런타임 변형보다 명시적 wiring, 결정적 검증, graph
tooling에 초점을 둡니다.

4.0.0의 stable baseline:

- 매크로 기반 컨테이너 API 생성
- 컴파일 타임과 빌드 타임 검증
- global dependency graph 렌더링과 DAG 검증
- `Lazy<T>`와 `Provider<T>` deferred edge
- `@SubContainer`, `@DIComponent`, `@DIHierarchyRoot`
- `InnoDISwiftUI`의 SwiftUI helper

## Topics

### Start Here

- <doc:Validation>
- <doc:PolicyBoundaries>
- <doc:ModuleWideInitDetection>

### Container API

- <doc:DIContainer>
- <doc:Provide>
- ``DIComponent()``
- ``DIHierarchyRoot()``
