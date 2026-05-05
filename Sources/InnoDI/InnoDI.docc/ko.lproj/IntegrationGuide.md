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
  제외합니다: `_storage_`, `_override_`, `_lazyCell_`, `_subBuildCell_`,
  `_innoDISubBuild_`, `_lazySelfForSub`.

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

container를 선언하는 각 target에 `InnoDIDAGValidationPlugin`을 붙입니다. plugin은 이제
build coordinator를 통해 DAG validator를 in-process로 실행합니다. standalone
`InnoDI-DependencyGraph` executable은 local inspection과 CI artifact 용도로 계속 사용할 수 있습니다.

Derived data가 network volume에 있을 때는 local SwiftPM scratch path를 사용합니다.
scratch path는 local disk에 있고 writable해야 하며, `/tmp`는 OS와 CI 환경에 맞는 local
temporary directory로 바꿔야 할 수 있습니다.

```sh
swift build --scratch-path /tmp/innodi-cache
```

filesystem 분류와 lock recovery는 <doc:lock-safety>를 참고하세요.
