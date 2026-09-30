# 튜토리얼 5 — `@SubContainer`로 컨테이너 중첩하기

parent 컨테이너와 child 컨테이너를 조합해, feature가 애플리케이션 root의 공유
input에 계속 접근하면서도 자기 scope를 갖게 합니다.

## 목표

`@SubContainer`와 `with:` key path 형식으로 연결되고, parent 인스턴스마다
`FeatureService`를 하나씩 소유하는 `FeatureContainer`.

## 코드

<!-- innodi:compile -->
```swift
import InnoDI

struct AppConfig {
    let baseURL: String
}

struct FeatureService {
    init(config: AppConfig) { self.config = config }
    let config: AppConfig
    func describe() -> String { "feature service for \(config.baseURL)" }
}

@DIContainer
struct FeatureContainer {
    @Input
    var config: AppConfig

    @Provide(.shared, FeatureService.self, with: [\Self.config])
    var service: FeatureService
}

@DIContainer
struct AppContainer {
    @Input
    var config: AppConfig

    @SubContainer(scope: .shared, with: [\Self.config])
    var feature: FeatureContainer
}

let container = AppContainer(config: AppConfig(baseURL: "https://example.com"))
print(container.feature.service.describe())
```

## 매크로가 추가하는 것

* `@SubContainer(scope: .shared, with: [\Self.config])`는 parent 인스턴스마다
  `FeatureContainer`를 하나 만들고, parent의 `config` 멤버를 같은 이름의 child
  input으로 넘기라고 매크로에 알립니다.
* 이제 parent의 중첩 `Overrides` builder가 child용 slot 두 개를 노출합니다.
  `feature`(전체 교체)와 `featureOverrides`(child 자신의 builder에 넘길
  overrides 클로저)입니다. child에 아직 override할 멤버가 없어도 둘 다 계속
  제공됩니다.
* wiring이 `with:`를 쓰므로 parent와 child의 멤버 이름이 같아야 합니다.
  label이 다르면 `bindings:`로 바꾸세요.
  `bindings: [(child: \FeatureContainer.config, parent: \Self.config)]`.

## `.shared`와 `.transient` 중 고르기

* `.shared`: child는 parent를 초기화할 때 한 번 만들어지고, 읽을 때마다
  재사용됩니다. 내부 `.shared` 그래프가 안정적으로 유지돼야 하는 coordinator
  같은 child에 쓰세요.
* `.transient`: 읽을 때마다 새 child를 만듭니다. child가 오래 사는 소유자가
  아니라 wiring namespace인 화면 단위나 요청 단위 scope에 쓰세요.

## 해 보기

* 테스트에서 child 전체를 override해 보세요.
  `overrides.feature = FeatureContainer(config: testConfig)`.
* 대신 overrides 블록을 넘길 수도 있습니다.
  `overrides.featureOverrides = { $0.service = FeatureService(config: testConfig) }`.
* 모듈을 넘나드는 소유를 위해 child에
  `@DIContainerRole(role: ContainerRole.component)`를 붙이고, 모듈 간 표면은
  <doc:DIContainer>를 다시 읽어 보세요.

## 다음에 읽을 문서

- <doc:Validation>
- <doc:DAGValidation>
- <doc:MigrationGuide>
