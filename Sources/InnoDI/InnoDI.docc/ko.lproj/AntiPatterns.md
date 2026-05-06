# Anti-Patterns

InnoDI는 runtime state container가 아니라 compile-time wiring boundary로
사용하세요. 아래 패턴은 dependency graph를 리뷰하기 어렵게 만들고,
InnoDI가 제공하는 validation 효과를 약하게 만듭니다.

## Service Locator처럼 쓰는 컨테이너

generic `resolve(_:)` 메서드 뒤로 lookup을 숨기거나 feature 코드에 전체
container를 넘기지 마세요.

```swift
// 피하세요
final class FeatureModel {
    let container: AppContainer

    func load() async throws {
        try await container.apiClient.fetch()
    }
}
```

feature가 실제로 필요한 dependency만 노출하세요.

```swift
struct FeatureModel {
    let apiClient: any APIClientProtocol
}
```

container는 root boundary에서 graph를 만들고, feature logic은 명시적 값을
받는 쪽이 좋습니다.

## 컨테이너 안의 런타임 상태

UI state, navigation state, modal store, mutable view-model state를 DI
container에 저장하지 마세요. Container는 graph construction surface입니다.

런타임 상태는 app layer나 companion framework layer에 둡니다. 예를 들어
modal presentation state는 flow/router layer가 소유하고, InnoDI는 그 flow가
필요로 하는 service를 제공하는 정도로 경계를 잡습니다.

## Generated storage 직접 접근

`_storage_*`, `_override_*`, `_innoDI*` 같은 generated storage를 직접 읽거나
쓰지 마세요. 이 이름들은 macro가 안전하게 진화하기 위한 implementation
detail이며 reserved surface입니다.

대신 public generated accessor, synthesized initializer, `withOverrides` API를
사용하세요.

## 오래 살아남는 test override

override가 많이 들어간 container를 여러 테스트에 걸쳐 재사용하지 마세요.
production wiring이 아니라 override graph를 테스트하게 되기 쉽습니다.

테스트마다 작은 override를 만드는 편이 안전합니다.

```swift
let container = AppContainer(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
}
```

교체가 한 operation에만 필요하다면 `withOverrides`를 사용하세요.

## Companion framework 경계 실수

feature가 `ModalStore`, router store, flow store를 사용한다면, generated DI
accessor에서 그 store를 직접 mutate하거나 container 안에 숨기지 마세요.
InnoDI는 service와 feature root를 구성하고, runtime transition과 state
mutation은 companion framework가 소유해야 합니다.

## 함께 보기

- <doc:PolicyBoundaries>
- <doc:Validation>
- <doc:MigrationGuide>
