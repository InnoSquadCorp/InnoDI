# SwiftUI Preview Helper

`#PreviewWithContainer` lives in `InnoDISwiftUI` and wraps Xcode 16's
`#Preview` so a preview body declares its container once. The macro expands to
a `DIContainerHost`: it defers container creation until mount, preserves one
generation across body redraws, and gives separate preview instances separate
owners even when the constructor payload is identical.

Use it when a SwiftUI feature root already comes from an InnoDI container and
the preview should exercise the same generated accessor that production code
uses. Keep the preview container local to the preview source file so override
state does not leak across unrelated previews.

Request the generated host overload explicitly in the container source file:

```swift
import SwiftUI
import InnoDISwiftUI
import InnoDI

// Inside the parent container:
@SubContainer(scope: .shared, featureRoots: [FeatureRoot(DashboardRootView.self, hosted: true)])
var dashboard: DashboardContainer
```

The opting-in file must import both modules; `canImport` only tests whether a
module is discoverable and cannot establish file-level name visibility. Other
feature roots emit only their zero-argument helper, regardless of which unrelated
targets have already been built. Then use the generated host overload:


```swift
parent.dashboardRootView(
    identity: route.id,
    close: { child in await child.scope.close() }
)
```

The identity-taking overload is lazy and host-owned; the zero-argument helper
remains available for source compatibility and direct construction. A hosted
root can read `@Environment(\.innoDIContainerHostHandle)` to perform an
explicit route, document, or window close. Do not treat a temporary
`onDisappear` as permanent closure.

See `Examples/PreviewInjectionExample/Sources/PreviewInjectionExample/PreviewInjectionExampleApp.swift`
for live, preview, and failure scenarios after migration.
