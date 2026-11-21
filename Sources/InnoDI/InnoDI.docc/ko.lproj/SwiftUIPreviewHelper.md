# SwiftUI Preview Helper

`#PreviewWithContainer`는 `InnoDISwiftUI`에 있으며, Xcode 16의 `#Preview`를
감싸 preview body가 컨테이너를 한 번만 선언하게 합니다. 매크로는
`DIContainerHost`로 전개됩니다. mount될 때까지 컨테이너 생성을 미루고, body를
다시 그려도 한 generation을 유지하며, 생성자 payload가 같아도 preview
인스턴스마다 별도의 owner를 줍니다.

SwiftUI feature root가 이미 InnoDI 컨테이너에서 나오고, preview가 production
코드와 같은 생성 helper를 그려야 할 때 쓰세요. override 상태가 관계없는
preview로 새지 않도록 preview 컨테이너는 preview 소스 파일 안에 두세요.

## Hosted feature root

컨테이너 소스 파일에서 host overload 생성을 명시적으로 요청하세요.

```swift
import SwiftUI
import InnoDISwiftUI
import InnoDI

// 부모 컨테이너 안에서:
@SubContainer(scope: .transient, featureRoots: [FeatureRoot(DashboardRootView.self, hosted: true)])
var dashboard: DashboardContainer
```

요청한 파일은 두 모듈을 모두 import해야 합니다. `canImport`는 모듈의 탐색 가능성만
확인하며 파일의 이름 가시성을 보장하지 않습니다. 다른 feature root는 관계없는
타깃의 빌드 여부와 무관하게 0-argument helper만 생성합니다. 이제 host overload를
호출할 수 있습니다.


```swift
parent.dashboardRootView(
    identity: route.id,
    close: { child in await child.scope.close() }
)
```

`.transient` child에서 identity를 받는 overload는 lazy이고 host가 소유합니다.
host는 mount된 뒤에야 child를 만들고, 다시 그려도 그 child 하나를 유지하며, 다음
identity가 그것을 대체하거나 lifecycle handle이 닫을 때 그 child를 `close`에
넘깁니다. 인자가 없는 helper는 소스 호환성과 직접 생성을 위해 계속 제공됩니다.
host된 root는 `@Environment(\.innoDIContainerHostHandle)`를 읽어 route, document,
window를 명시적으로 닫을 수 있습니다. 일시적인 `onDisappear`를 영구적인 닫힘으로
다루지 마세요.

`.shared` child는 부모의 것입니다. 부모가 초기화 중에 만들고 읽을 때마다 같은
인스턴스를 돌려줍니다. host는 그것을 보여줄 수는 있지만 소유할 수는 없으므로, hosted
overload는 close 훅이 없는 `dashboardRootView(identity:)`입니다. 모든 identity가
부모의 child 하나를 보여주며 host는 그것을 닫지 않습니다. 7.0의
`dashboardRootView(identity:close:)` 표기는 계속 컴파일되고 동작도 같지만, `.shared`
child에서는 deprecated입니다. 부모가 계속 제공하는 인스턴스를 identity가 바뀔 때마다,
그리고 명시적으로 닫을 때마다 훅에 넘기기 때문입니다. route, document, window마다
host가 닫는 별도 child가 필요하면 child를 `.transient`로 선언하세요.

## Preview

Swift는 `#PreviewWithContainer`나 `#Preview` 같은 file-scope 매크로의 인자를
다른 매크로가 생성한 멤버가 보이기 전에 type-check합니다. 그래서 `@DIContainer`
initializer를 호출하는 인자나, 생성된 feature-root helper를 호출하는 closure body는
`'AppContainer' cannot be constructed because it has no accessible initializers`
같은 오류로 컴파일되지 않습니다. 같은 선언은 일반 함수, static 멤버, view body
안에서는 컴파일되므로, 컨테이너는 함수에서 만들고 생성 helper는 작은 wrapper
view에서 그리세요.

<!-- innodi:compile-library -->
```swift
import InnoDISwiftUI
import SwiftUI

@DIContainer
struct DashboardContainer {
    @Input var baseURL: String
}

struct DashboardRootView: View {
    let container: DashboardContainer

    var body: some View {
        Text(container.baseURL)
    }
}

@DIContainer
struct AppContainer {
    @Input var baseURL: String

    @SubContainer(scope: .transient, with: [\Self.baseURL], featureRoot: DashboardRootView.self)
    var dashboard: DashboardContainer
}

// 생성된 initializer와 helper는 #PreviewWithContainer 인자가 아니라
// 일반 선언 안에서 호출합니다.
func makePreviewApp() -> AppContainer {
    AppContainer(baseURL: "https://example.com")
}

struct AppPreviewRoot: View {
    let container: AppContainer

    var body: some View {
        container.dashboardRootView()
    }
}

#PreviewWithContainer(makePreviewApp()) { container in
    AppPreviewRoot(container: container)
}
```

`AppContainer.preview()`처럼 extension에 둔 static factory도 함수와 같은 방식으로
동작합니다. 매크로는 라이브러리나 앱 소스 파일의 file scope에 쓰세요.
`main.swift`의 top-level 코드는 이 매크로를 문장(statement)으로 읽습니다.

마이그레이션 뒤의 live, preview, 실패 시나리오는
`Examples/PreviewInjectionExample/Sources/PreviewInjectionExample/PreviewInjectionExampleApp.swift`를
참고하세요.
