# Assisted Factory와 Collection

Child에 호출 시점의 입력이 필요하거나 모듈이 순서 있는 기여값을 내보낸다면
명시적 구성을 사용하세요. 이 API는 현재 7.0.1의 일부이며 runtime 등록이나
암묵적인 모듈 탐색을 하지 않습니다.

## 구성 경계 선택

- `@SubContainer`: 부모가 입력을 제공하는 고정 child
- `@SubContainerFactory`: assisted input을 받는 child의 부모 소유 factory
- `@Multibinding`: 동기 sibling 의존성의 typed 배열
- Collection value/provider 타입: 모듈이 내보낸 값을 명시적으로 조합

선언하는 모든 target에 validation plugin을 연결하세요. 다른 파일이나 모듈이
factory 타입을 참조할 수 있도록 child 안에 source-visible 선언을 두세요.

## Assisted Child 입력

일반 `@Input` 값은 child factory가 보관하고 `@Input(.assisted)` 값은 factory
호출 시 인자로 전달합니다. 매크로와 명시적인 static/assisted 목록을 붙인 빈
nested `AssistedFactory`를 선언하세요.

<!-- innodi:compile -->
```swift
import InnoDI

struct Repository {}

@DIContainer
struct SessionContainer {
    @Input var repository: Repository
    @Input(.assisted) var sessionID: Int

    @AssistedFactory(
        SessionContainer.self,
        static: [\SessionContainer.repository],
        assisted: [\SessionContainer.sessionID]
    )
    struct AssistedFactory {}
}

@DIContainer
struct AppContainer {
    @Input var repository: Repository

    @SubContainerFactory(
        SessionContainer.self,
        bindings: [(child: \SessionContainer.repository, parent: \Self.repository)]
    )
    var session: SessionContainer.AssistedFactory
}

let app = AppContainer(repository: Repository())
let first = app.session(sessionID: 1)
let second = app.session(sessionID: 2)
precondition(first.sessionID == 1 && second.sessionID == 2)
```

부모 `bindings:`는 일반 child input을 각각 정확히 한 번 연결하고 assisted
input은 연결하지 않아야 합니다. 부모 경로는 canonical `\Self.member`를 쓰고,
child 경로는 해당 child의 input을 가리킵니다. Factory를 호출할 때마다 child가
생성되고 내부 `.shared` provider는 그 새 child에 속합니다. 부모의 static 값은
여러 child 사이에서 공유될 수 있습니다. Factory 자체를 만들 때 static binding을
해석하므로 부모의 on-demand provider를 즉시 읽을 수 있습니다.

다른 모듈의 child에는 `@DIContainerRole(role: ContainerRole.component)`를
사용하고 child, input, nested factory를 필요한 접근 수준으로 노출하세요.
접근 제어는 같은 파일의 internal 예제만으로 판단하지 말고 저장소의 cross-module
external consumer fixture를 참고하세요.

이 factory가 owned async 수명주기를 자동으로 만들지는 않습니다. Owned scope와
identity 기반 host는 <doc:OwnedContainers>와 <doc:SwiftUIPreviewHelper>를
참고하고, 기능을 조합하기 전에 지원되는 형태를 확인하세요.

## 순서 있는 값과 Keyed 값

`@Multibinding`은 contributor 순서를 유지합니다. Contributor는 선언된 배열
요소 타입에 할당 가능한 동기 direct managed member여야 합니다. 생성된 Swift
배열이 assignability를 검사하므로 existential 배열에 concrete 값을 넣을 수도
있습니다. 빈 `[]`는 명시적인 빈 기여를 뜻합니다.

<!-- innodi:compile -->
```swift
import InnoDI

protocol Service { var name: String { get } }
struct AuthService: Service { let name = "auth" }
struct LogService: Service { let name = "log" }

@DIContainer
struct AppContainer {
    @Provide(.shared, factory: AuthService()) var auth: AuthService
    @Provide(.transient, factory: LogService()) var log: LogService
    @Multibinding([\Self.auth, \Self.log]) var services: [any Service]
}

let app = AppContainer()
precondition(app.services.map(\.name) == ["auth", "log"])

let first = DICollectionGroup([1, 2])
let second = DICollectionGroup([3])
precondition(Array(DICollectionGroup.compose([first, second])) == [1, 2, 3])

let keyed = try DIKeyedCollection<String, Int>([
    .init(key: "auth", value: 1),
    .init(key: "log", value: 2),
])
precondition(keyed[key: "auth"] == 1)
```

Multibinding을 읽으면 각 contributor의 accessor를 통해 값을 읽어 해당 lifetime과
override를 유지합니다. Collection 자체에도 override slot이 있습니다.
`DICollectionGroup.compose`는 지정한 group을 호출자 순서대로 연결합니다.
`DIKeyedCollection`은 entry 순서를 유지하고 key 조회에서 optional 값을 반환합니다.
생성이나 조합 중 key가 중복되면 `DIKeyedCollectionDuplicateError`를 던지며,
앞선 기여를 조용히 덮어쓰지 않습니다.

## 지연 Collection과 Graph Metadata

`DIProviderCollection`은 동기 closure를 저장하고 선택한 index만 해석합니다.
`DIKeyedProviderCollection`은 선택한 key를 해석하거나, `callAsFunction()`으로
해석하는 entry를 제공합니다. 반복해서 읽으면 closure가 다시 호출되며 cache는
그 closure가 참조하는 target의 계약에 따릅니다. Provider collection 전체를
순회하면 선택한 모든 요소가 해석될 수 있습니다. Provider collection이 async
지원이나 `Sendable` 준수를 보장하는 것은 아닙니다.

Runtime 구성과 graph metadata는 별개입니다. Factory로 만든 collection은
`@Provide(collection:)`에 `.ordered`, `.keyed`, `.providers`, `.keyedProviders`를
지정할 수 있습니다. Metadata는 literal canonical direct-member key path를 쓰며
keyed entry는 `.init(key: "id", contributor: \Self.member)` 형태입니다.
이는 선언된 graph를 설명하며 factory 본문을 분석하거나 바꾸지 않습니다.
실제 생성과 metadata를 일치시키세요. 명시적인 빈 metadata는 metadata 생략과
다릅니다. Schema-v6 graph diff는 순서, key, contributor identity와 lifetime을
포함합니다. 검토 방법은 <doc:DAGValidation>을 참고하세요.

## 다음 단계

- <doc:Tutorial-05-SubContainer>: 고정 child wiring과 child override
- <doc:Provide>: 생성, effect와 동기 deferred wrapper
- <doc:OwnedContainers>: 준비, readiness와 명시적 정리
- <doc:MigrationGuide>: 이전 표기와 제거된 prototype API
- <doc:DocumentationGuide>: 전체 작업별 문서 안내
