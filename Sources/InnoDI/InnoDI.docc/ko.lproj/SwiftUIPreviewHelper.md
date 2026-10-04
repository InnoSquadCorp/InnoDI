# SwiftUI Preview Helper

`#PreviewWithContainer`는 `InnoDISwiftUI`에 있으며, Xcode 16의 `#Preview`를
감싸 preview body가 컨테이너를 한 번만 선언하게 합니다. 매크로는
`DIContainerHost`로 전개됩니다. mount될 때까지 컨테이너 생성을 미루고, body를
다시 그려도 한 generation을 유지하며, 생성자 payload가 같아도 preview
인스턴스마다 별도의 owner를 줍니다.

SwiftUI feature root가 이미 InnoDI 컨테이너에서 나오고, preview가 production
코드와 같은 생성 accessor를 실행해야 할 때 쓰세요. override 상태가 관계없는
preview로 새지 않도록 preview 컨테이너는 preview 소스 파일 안에 두세요.

컨테이너 소스 파일에서 host overload 생성을 명시적으로 요청하세요.

```swift
import SwiftUI
import InnoDISwiftUI
import InnoDI

// 부모 컨테이너 안에서:
@SubContainer(scope: .shared, featureRoots: [FeatureRoot(DashboardRootView.self, hosted: true)])
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

identity를 받는 overload는 lazy이고 host가 소유합니다. 인자가 없는 helper는
소스 호환성과 직접 생성을 위해 계속 제공됩니다. host된 root는
`@Environment(\.innoDIContainerHostHandle)`를 읽어 route, document, window를
명시적으로 닫을 수 있습니다. 일시적인 `onDisappear`를 영구적인 닫힘으로 다루지
마세요.

마이그레이션 뒤의 live, preview, 실패 시나리오는
`Examples/PreviewInjectionExample/Sources/PreviewInjectionExample/PreviewInjectionExampleApp.swift`를
참고하세요.
