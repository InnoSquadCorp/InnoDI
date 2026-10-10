# 문서 안내

하려는 작업에 맞는 현재 API 안내부터 읽으세요. 이 문서는 InnoDI 7.0.1을
기준으로 합니다. 다른 버전을 설치했다면 해당 릴리스 tag의 소스를 보세요.

## 설치와 첫 사용

저장소 README에 전체 SwiftPM 설치 절차와 플랫폼 요구 사항이 있습니다.
`InnoDI`와 필요한 경우 `InnoDISwiftUI`를 추가하고, 컨테이너 또는 standalone
`@DIEnvironmentBridge`를 선언하는 모든 target에 `InnoDIDAGValidationPlugin`을
연결하세요. 패키지를 추가하는 것만으로 플러그인이 연결되지는 않습니다.
테스트 도구를 사용한다면 test 또는 preview-support target에 `InnoDITesting`을
추가하세요.

- <doc:GettingStarted>: 단계별 첫 컨테이너
- <doc:Tutorial-01-Hello>: 작은 동기 애플리케이션
- <doc:Tutorial-02-Inputs>: 생성 시 전달하는 값
- <doc:Tutorial-03-Wiring>: 이름으로 연결하는 factory 의존성
- <doc:Tutorial-04-Concrete>: concrete 타입과 protocol 저장소
- <doc:IntegrationGuide>: SwiftPM, Xcode, Tuist, lint와 format 통합
- <doc:lock-safety>: 로컬 scratch 저장소와 파일시스템 제약

최소 Swift tools 버전은 6.2이며, 지원 배포 대상은 iOS 17, macOS 14,
watchOS 10, tvOS 17, visionOS 1 이상입니다. Linux는 지원되는 패키지 구성이
아닙니다. SwiftSyntax는 604.0.0에 고정되어 Mockable 0.6.4의 버전 범위와
충돌합니다. 다른 매크로 패키지를 선택하기 전에 소비자 전체 graph의 의존성
해석을 확인하세요.

## API와 구성 안내

| 작업 | API | 안내 |
| --- | --- | --- |
| 앱 graph 정의 | `@DIContainer`, `@DIContainerRole` | <doc:DIContainer> |
| 설정 또는 runtime 값 전달 | `@Input`, `@Input(escaping: true)` | <doc:Provide> |
| 공유 값 또는 새 값 생성 | `@Provide`, `.shared`, `.transient`, `factory:`, `asyncFactory:` | <doc:Provide> |
| 동기 작업 지연 또는 선택적 사전 준비 | `.onDemand`, `prewarm`, `Lazy`, `Provider` | <doc:Provide> |
| 고정 child 연결 | `@SubContainer`, `with:`, `bindings:` | <doc:Tutorial-05-SubContainer> |
| 호출 시 인자를 받는 child 생성 | `@Input(.assisted)`, `@AssistedFactory`, `@SubContainerFactory` | <doc:Composition> |
| 모듈별 기여값 조합 | `@Multibinding`, `DICollectionGroup`, keyed/provider collection | <doc:Composition> |
| graph 계약과 역방향 영향 확인 | `InnoDI-DependencyGraph` | <doc:DAGValidation> |
| 생성된 runtime event 연결 | `DITraceContext`, `DIBoundedTraceBuffer` | <doc:RuntimeTracing> |

Factory 파라미터 이름과 canonical direct-member `\Self.member` 경로가
명시적 graph edge를 정의합니다. 임의의 factory 본문 참조를 자동 발견하지는
않습니다. `validateDAG: false`는 제한된 escape hatch이며 ownership, 선언,
effect 검사를 우회하는 옵션이 아닙니다. <doc:PolicyBoundaries>와
<doc:PluginOptOut>을 참고하세요.

## 수명주기와 SwiftUI

- <doc:OwnedContainers>: 선택적인 generated ownership, `makeOwned`, 선택한
  `prepare`, retry, `withPrepared`, await하는 `close`
- <doc:AsyncPreparation>: 일반 async provider와 수동 `DIAsyncScope`
- <doc:Provide>: eager/on-demand 생성과 취소
- <doc:SwiftUIPreviewHelper>: feature-root helper,
  `DIContainerHost`, identity, preview와 명시적 종료

비동기 factory를 추가하기 전에 수명주기를 정하세요. `makeOwned`는 준비 완료를
뜻하지 않습니다. report를 반환하는 준비에서는 `report.isReady`를 확인하세요.
일반 eager async shared provider는 초기화 중 시작되며 컨테이너가 취소하지
않습니다. Async on-demand provider에는 throwing accessor와
`closeAsyncProviders()`가 있습니다. Generated owner는 명시적인 종료가 필요하며,
빌려온 input 자원이나 서비스 내부의 임의 task를 소유하지 않습니다. SwiftUI
화면이 사라졌다고 반드시 소유권이 끝난 것은 아닙니다.

## 테스트와 오류 복구

Generated `Overrides`/`withOverrides`로 runtime 등록 컨테이너 없이 의존성을
교체하세요. <doc:AutoMock>은 `@GenerateMock`, stub 검증, 호출 내역과 reset
경계를 설명합니다. `InnoDITesting`은 `DIOverridePreset`, MainActor 호환 validation adapter,
effect 검증과 typed helper를 제공합니다. [전용 모듈 reference](https://github.com/InnoSquadCorp/InnoDI/blob/main/Sources/InnoDITesting/InnoDITesting.docc/InnoDITesting.md)에 자세한 API가 있습니다.

오류가 발생하면 출력된 diagnostic identifier부터 확인하세요.

- <doc:DiagnosticsGuide>: 진단별 복구 절차
- <doc:Validation>: 오류를 검출하는 단계
- <doc:ModuleWideInitDetection>: 여러 파일의 initializer 충돌
- <doc:PolicyBoundaries>: 지원하지 않는 선언, 격리와 wiring
- <doc:AntiPatterns>: 피해야 할 graph 설계

Migration 전에 읽기 전용 Doctor를 실행하세요. 설치한 버전과 일치하는
InnoDI checkout에서 아래 명령을 실행하고 소비자 경로를 바꾸세요.

```bash
swift run InnoDI-Doctor --root /path/to/consumer
swift run InnoDI-Migrate --root /path/to/consumer --check
swift run InnoDI-Migrate --root /path/to/consumer --report
swift run InnoDI-DependencyGraph --root /path/to/consumer --validate-dag
```

쓰기 모드를 사용하기 전에 report를 검토하세요. Parse, Doctor report 또는
graph 검사가 성공해도 소비자 빌드 성공을 뜻하지 않습니다. 실제 isolation과
import 설정으로 Apple target을 빌드하고 테스트하세요. 변경한 소스를 검토할
때까지 보고된 `RECOVERY` 파일을 보관하세요.

## 업그레이드와 문서 언어

- <doc:MigrationGuide>: 6.x → 7.0을 포함한 버전별 소스 변경
- <doc:MigratingFromFactory>: Factory와 공존하거나 대체하여 도입
- <doc:MigratingFromSwinject>: runtime 등록을 명시적 wiring으로 이전

저장소 `CHANGELOG.md`가 릴리스·업그레이드의 기준입니다. `docs/plans`,
`docs/reviews`, `docs/rfcs`와 예전 changelog는 과거 근거를 보존합니다.
그 안의 제안과 오래된 코드는 현재 API 사용 예제가 아닙니다. Examples는 로컬
checkout을 사용하고 README의 package snippet은 공개 릴리스를 선택합니다.
과거 7.0.0 fixture 통과를 실제 7.0.1 소비자의 검증 근거로 취급하지 마세요.

영어가 전체 canonical reference이며 한국어는 영어 README와 DocC article
소스를 함께 유지합니다. 일본어, 중국어 간체, 독일어, 스페인어, 러시아어
README는 전체 reference로 연결하는 현재 버전의 요약 안내입니다. 해당 언어의
DocC 디렉터리는 여전히 과거 6.0.0 번역 안내입니다. 생성하는 DocC archive는
영어 catalog를 빌드합니다. 저장소에 번역 소스가 있다고 공개 archive에 언어
선택기가 있다는 뜻은 아닙니다.
