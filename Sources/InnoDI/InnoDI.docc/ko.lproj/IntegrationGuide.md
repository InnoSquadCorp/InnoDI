# 통합 가이드

InnoDI는 generated Swift source와 build-time validation을 함께 쓰는 도구입니다.
대부분의 도구는 macro output을 compiler-generated implementation detail로 보고,
사용자가 작성한 container 선언을 리뷰 표면으로 유지할 때 가장 잘 동작합니다.

## Periphery

- hand-written source glob 대신 generated build setting을 기준으로 Periphery를 실행해
  macro-expanded member가 compiler에 보이도록 합니다.
- `@DIContainer`, `@Provide`, `@SubContainer`, generated override entry point가
  reflection-free wiring에서만 호출된다면 테스트, sample app, explicit retention rule로
  reachable하게 유지합니다.
- generated-member noise는 전체 모듈을 ignore하기보다 container type이나 public entry point를
  retain하는 방식으로 줄이는 편이 좋습니다.

## SwiftLint

- 사용자가 작성한 source는 일반적인 방식으로 lint합니다.
- macro-expanded output을 hand-written code처럼 lint하지 않습니다.
- generated interface artifact를 검사하는 설정이라면 InnoDI reserved generated prefix를
  제외합니다: `_storage_`, `_override_`, `_innoDI`, `_InnoDI`.

## SwiftFormat

- 직접 작성한 container declaration을 formatting 대상으로 둡니다.
- consumer project에서 macro expansion snapshot에 별도 formatting pass를 요구하지 않습니다.
- attribute와 factory closure는 declaration site에서 읽기 쉽게 유지합니다. 그 source가
  reviewer가 확인해야 할 표면입니다.

## 매크로 생성 멤버

InnoDI는 container declaration에서 initializer, storage, override, helper closure를
생성합니다. generated member는 compiled API surface의 일부로 취급하되, 수동 dependency는
source container에 명시적으로 남깁니다.

도구가 generated symbol을 보고하면, actionable 여부를 판단하기 전에 가장 가까운
`@DIContainer`, `@Provide`, `@SubContainer` 선언으로 매핑합니다.

## 빌드 플러그인

container 또는 standalone `@DIEnvironmentBridge`를 선언하는 각 target에
`InnoDIDAGValidationPlugin`을 붙입니다. attached macro는 sibling extension, 모든
enclosing declaration, 같은 target의 다른 source를 검사할 수 없으므로 이는 5.0
정확성 계약의 필수 구성입니다. target-scoped full-source pass는 같은 파일과
다른 파일 extension의 matching custom initializer, enclosing 또는 같은 target의
generated qualifier shadow, 현재 target에서 보이는 imported dependency target의
`public` 또는 `package` qualifier shadow, bridge의 direct-extension attachment와
standalone local target을 Swift compile 전에 차단합니다.

5.1부터 이 package plugin은 `XcodeBuildToolPlugin`도 지원합니다. 네이티브 Xcode
project 또는 Tuist가 생성한 project의 모든 container target에 직접 연결하세요.
Tuist workspace에서는 workspace root를 찾고 하나의 production-source snapshot을
만들어 교차 project container 참조를 source-level validation에 포함합니다.

Xcode plugin API는 Tuist의 전체 교차 project target dependency topology를 제공하지
않습니다. 따라서 Tuist fallback은 full source DAG와 declaration contract를 검증하지만,
정확한 target graph에 의존하는 module-edge hierarchy 규칙은 topology-aware SwiftPM
또는 CI 검증이 추가로 필요합니다. multi-destination variant가 하나의 plugin work
directory를 공유할 수 있어 Xcode command는 output을 선언하지 않으며, Xcode가 매
build마다 validation을 schedule할 수 있습니다.

Class bridge 또는 class 안에 중첩된 container/bridge는 첫 inherited type을
잠재적인 superclass로 따라갑니다. 따라가는 모든 class와 typealias는 workspace
snapshot에서 source-visible해야 합니다. SDK·binary에만 있거나 해소되지 않거나
모호한 첫 inherited type은 `generated-qualifier.inheritance-unverifiable`로
거부됩니다. 외부 hierarchy를 index할 수 없다면 struct/enum 또는 source-visible
adapter를 사용하세요. Syntax-only index는 bridge 생성에 쓰이는 상속된 `Swift`와
`SwiftUI` type member를 보수적으로 거부하지만 상속된 `InnoDISwiftUI` member는
허용합니다. 직접 또는 enclosing scope의 `InnoDISwiftUI` declaration은 계속
예약됩니다.

plugin은 이제 build coordinator를 통해 DAG validator를 in-process로 실행합니다.
standalone `InnoDI-DependencyGraph` executable은 local inspection과 CI artifact
용도로 계속 사용할 수 있습니다.

Derived data가 network volume에 있을 때는 local SwiftPM scratch path를 사용합니다.
scratch path는 local disk에 있고 writable해야 하며, `/tmp`는 OS와 CI 환경에 맞는 local
temporary directory로 바꿔야 할 수 있습니다.

```sh
swift build --scratch-path /tmp/innodi-cache
```

filesystem 분류와 lock recovery는 <doc:lock-safety>를 참고하세요.
