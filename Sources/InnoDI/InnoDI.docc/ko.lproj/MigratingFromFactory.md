# Factory에서 옮기기

런타임 Factory 컨테이너의 등록을 생성된 InnoDI 컨테이너로 옮깁니다.

## Overview

Factory는 공유 컨테이너에서 런타임에 의존성을 해석하며, 보통
`@Injected(\.service)` 같은 key-path property wrapper를 사용합니다. InnoDI는
대신 컨테이너 initializer를 생성하고, 매크로 전개와 빌드 플러그인 단계에서
의존성 그래프를 검증합니다. 그래서 두 가지를 옮기게 됩니다. 등록은
`@DIContainer`의 `@Provide` 멤버가 되고, 해석은 명시적인 initializer 또는
factory 클로저 파라미터가 됩니다.

InnoDI에는 의도적으로 `@Injected` property wrapper, 프로세스 전역 컨테이너,
런타임 등록 API가 없습니다. 타입은 initializer로 의존성을 받고, 컴포지션
루트가 컨테이너 값을 소유합니다.

## 개념 대응표

| Factory 3 | InnoDI |
|---|---|
| `extension Container { var api: Factory<API> { self { LiveAPI() } } }` | `@Provide(.transient, factory: LiveAPI()) var api: any API` |
| 기본 `.unique` 스코프 | `.transient` |
| `.singleton` | 앱이 한 번 만드는 루트 컨테이너의 `.shared`. InnoDI에는 프로세스 전역 스코프가 없고, 컨테이너 인스턴스가 수명입니다. |
| `.cached`와 `Container.shared.reset()` | `.shared`. 처음부터 다시 시작하려면 새 컨테이너를 만듭니다. |
| `.shared`(약한 참조) | 대응 없음. InnoDI는 강한 참조를 유지합니다. |
| `.graph` | 읽을 때마다 자식을 새로 만드는 `.transient` `@SubContainer`의 `.shared` 멤버 |
| `@Injected(\.api) var api` | initializer 파라미터. `{ (api: any API) in ViewModel(api: api) }` 같은 factory 클로저 파라미터가 값을 넘깁니다. |
| `Container.shared.api()` | 컴포지션 루트에서 `container.api` |
| `Container.shared.api.register { MockAPI() }` | `AppContainer(...) { $0.api = MockAPI() }` 또는 `AppContainer.withOverrides(...)` |
| `.onTest { }`, `.onPreview { }` | 생성된 `Overrides`로 만든 별도 테스트·프리뷰 컨테이너. 실제 provider에는 `effect: .sideEffect`를 표시하고 `InnoDITesting`으로 preset을 검증합니다. |
| `ParameterFactory<P, T>` | `@Input(.assisted)`와 `@AssistedFactory`, `@SubContainerFactory` |
| 런타임 순환 의존성 감지 | 컴파일·빌드 시점 순환 거부 |

## 옮기는 순서

1. 앱 진입점이나 기능 하나처럼 컴포지션 루트를 하나 고르고 `@DIContainer`를
   선언합니다. base URL이나 실행 설정처럼 Factory가 컨테이너 밖에서 읽던 값은
   `@Input` 멤버가 됩니다.
2. 각 등록을 `@Provide` 멤버로 옮깁니다. 스코프는 대응표에서 고르고, 형제
   의존성은 모두 factory 클로저 파라미터로 이름을 적어 InnoDI가 edge를
   기록하게 합니다.
3. 타입 안의 `@Injected`와 `Container.shared` 조회를 initializer 파라미터로
   바꿉니다. 컨테이너 멤버는 컴포지션 루트에서만 읽습니다.
4. 테스트·프리뷰 등록을 생성된 `Overrides` 빌더로 옮깁니다. 테스트가 자기
   컨테이너를 만들므로 케이스 사이에 공유 컨테이너를 reset할 필요가 없습니다.
5. 컨테이너를 선언하는 모든 타깃에 `InnoDIDAGValidationPlugin`을 붙이고, CI에서
   `swift run InnoDI-DependencyGraph --root . --validate-dag`를 실행합니다.

전환 중에는 Factory와 InnoDI를 함께 쓸 수 있습니다. 컴포지션 루트에서
Factory로 값을 해석해 InnoDI 컨테이너에 `@Input`으로 넘기고, 그 값을 읽는
타입이 없어지면 Factory 등록을 지웁니다.

## 예제

주석은 각 멤버가 대체하는 Factory 등록을 가리킵니다.

<!-- innodi:compile -->
```swift
import InnoDI

protocol WeatherAPI: Sendable {
    func temperature(for city: String) -> Int
}

struct LiveWeatherAPI: WeatherAPI {
    let baseURL: String
    func temperature(for city: String) -> Int { city.count }
}

struct StubWeatherAPI: WeatherAPI {
    func temperature(for city: String) -> Int { 21 }
}

final class ForecastViewModel {
    private let api: any WeatherAPI

    init(api: any WeatherAPI) {
        self.api = api
    }

    func headline(for city: String) -> String {
        "\(city): \(api.temperature(for: city))°"
    }
}

@DIContainer
struct AppContainer {
    @Input var baseURL: String

    // Factory: `self { LiveWeatherAPI(baseURL: ...) }.singleton`
    @Provide(.shared, factory: { (baseURL: String) in
        LiveWeatherAPI(baseURL: baseURL)
    })
    var weatherAPI: any WeatherAPI

    // Factory: `self { ForecastViewModel(api: self.weatherAPI()) }`
    @Provide(.transient, factory: { (weatherAPI: any WeatherAPI) in
        ForecastViewModel(api: weatherAPI)
    })
    var forecastViewModel: ForecastViewModel
}

let live = AppContainer(baseURL: "https://api.example.com")
print(live.forecastViewModel.headline(for: "Seoul"))

// Factory: `Container.shared.weatherAPI.register { StubWeatherAPI() }`
let preview = AppContainer(baseURL: "https://api.example.com") { overrides in
    overrides.weatherAPI = StubWeatherAPI()
}
print(preview.forecastViewModel.headline(for: "Seoul"))
```

## See Also

- <doc:MigratingFromSwinject>
- <doc:Provide>
- <doc:PolicyBoundaries>
