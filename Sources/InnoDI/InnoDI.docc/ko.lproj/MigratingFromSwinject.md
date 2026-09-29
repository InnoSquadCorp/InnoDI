# Swinject에서 옮기기

Swinject 등록과 assembly를 생성된 InnoDI 컨테이너로 옮깁니다.

## Overview

Swinject는 런타임에 `Container`에 factory를 등록하고 옵셔널을 돌려주는
`resolve(_:)`로 해석합니다. InnoDI는 대신 컨테이너 initializer를 생성하므로,
빠졌거나 타입이 틀린 의존성은 강제 언래핑이 아니라 컴파일·빌드 시점에
실패합니다. 각 등록은 `@Provide` 멤버로, 각 `r.resolve(...)` 호출은 이름 있는
factory 클로저 파라미터로 옮깁니다.

InnoDI에는 의도적으로 런타임 등록 API, 이름 기반 등록, 약한 object scope가
없습니다. late binding이나 plugin 방식 조합에는 여전히 런타임 컨테이너가 더
잘 맞습니다.

## 개념 대응표

| Swinject | InnoDI |
|---|---|
| `container.register(API.self) { _ in LiveAPI() }` | `@Provide(.shared, factory: LiveAPI()) var api: any API` |
| `.inObjectScope(.container)` | `.shared` |
| `.inObjectScope(.transient)` | `.transient` |
| 기본 `.graph` 스코프 | 읽을 때마다 자식을 새로 만드는 `.transient` `@SubContainer`의 `.shared` 멤버 |
| `.inObjectScope(.weak)` | 대응 없음. InnoDI는 강한 참조를 유지합니다. |
| 등록 안의 `r.resolve(Dependency.self)!` | `{ (dependency: Dependency) in ... }` 같은 이름 있는 factory 클로저 파라미터. 컴파일 시점에 검사합니다. |
| `register(_:name:)` | `primaryDatabase`, `cacheDatabase`처럼 이름이 다른 별도 멤버 |
| `register { (r, userID: Int) in ... }`와 `resolve(_:argument:)` | `@Input(.assisted)`와 `@AssistedFactory`, `@SubContainerFactory` |
| `Assembly`와 `Assembler` | 기능마다 `@DIContainer` 하나, 부모가 `@SubContainer`로 마운트. 다른 모듈이 마운트하는 기능은 `@DIContainerRole(role: ContainerRole.component)`를 씁니다. |
| 순환을 위한 `initCompleted` property injection | 지원하지 않습니다. InnoDI는 `Lazy`와 `Provider`를 거치는 순환을 포함해 모든 의존성 순환을 거부합니다. 공유 상태는 별도 의존성으로 옮기세요. |
| 테스트에서 mock 재등록 | 생성된 `Overrides` 빌더 또는 `withOverrides` |

## 옮기는 순서

1. `Assembly`를 하나씩 `@DIContainer`로 바꿉니다. 설정처럼 assembly가 밖에서
   읽던 값은 `@Input` 멤버가 됩니다.
2. 각 `register` 호출을 `@Provide` 멤버로 바꿉니다. 스코프는 대응표에서
   고릅니다. Swinject 기본 `.graph` 스코프는 직접 대응이 없으므로 값이
   `.shared`인지 `.transient`인지 정해야 합니다.
3. 각 `r.resolve(...)!`를 의존성 멤버 이름과 같은 factory 클로저 파라미터로
   바꿉니다.
4. 이름 기반 등록은 이름이 다른 멤버로, 인자를 받는 등록은 assisted factory로
   바꿉니다.
5. `initCompleted`에 기대던 순환을 끊습니다. 모든 컨테이너 타깃에
   `InnoDIDAGValidationPlugin`을 붙여 새 순환이 빌드에서 거부되게 합니다.

전환 중에는 Swinject와 InnoDI를 함께 쓸 수 있습니다. 컴포지션 루트에서
Swinject 컨테이너로 값을 해석해 InnoDI 컨테이너에 `@Input`으로 넘깁니다.

## 예제

주석은 각 멤버가 대체하는 Swinject 등록을 가리킵니다. 세션 컨테이너는
`resolve(_:argument:)`를 대체하는 assisted factory를 보여 줍니다.

<!-- innodi:compile -->
```swift
import InnoDI

final class Database {
    let path: String

    init(path: String) {
        self.path = path
    }
}

final class SessionStore {
    let userID: Int
    let database: Database

    init(userID: Int, database: Database) {
        self.userID = userID
        self.database = database
    }
}

@DIContainer
struct SessionContainer {
    @Input(.assisted) var userID: Int
    @Input var database: Database

    @Provide(.shared, factory: { (userID: Int, database: Database) in
        SessionStore(userID: userID, database: database)
    })
    var store: SessionStore

    @AssistedFactory(
        SessionContainer.self,
        static: [\SessionContainer.database],
        assisted: [\SessionContainer.userID]
    )
    struct AssistedFactory {}
}

@DIContainer
struct AppContainer {
    // Swinject: `register(Database.self) { _ in ... }.inObjectScope(.container)`
    @Provide(.shared, factory: Database(path: "app.sqlite"))
    var database: Database

    // Swinject: `register(SessionStore.self) { (r, userID: Int) in ... }`
    @SubContainerFactory(
        SessionContainer.self,
        bindings: [(child: \SessionContainer.database, parent: \Self.database)]
    )
    var session: SessionContainer.AssistedFactory
}

let app = AppContainer()
let session = app.session(userID: 42)
print(session.store.userID, session.store.database === app.database)
```

## See Also

- <doc:MigratingFromFactory>
- <doc:DIContainer>
- <doc:PolicyBoundaries>
