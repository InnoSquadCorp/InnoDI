# SwiftUI Preview Helper

`#PreviewWithContainer` lives in `InnoDISwiftUI` and wraps Xcode 16's
`#Preview` so a preview body declares its container once. The macro expands to
a `DIContainerHost`: it defers container creation until mount, preserves one
generation across body redraws, and gives separate preview instances separate
owners even when the constructor payload is identical.

Use it when a SwiftUI feature root already comes from an InnoDI container and
the preview should render the same generated helper that production code uses.
Keep the preview container local to the preview source file so override
state does not leak across unrelated previews.

## Hosted feature roots

Request the generated host overload explicitly in the container source file:

```swift
import SwiftUI
import InnoDISwiftUI
import InnoDI

// Inside the parent container:
@SubContainer(scope: .transient, featureRoots: [FeatureRoot(DashboardRootView.self, hosted: true)])
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

For a `.transient` child the identity-taking overload is lazy and host-owned:
the host builds the child only after mount, keeps that one child across
redraws, and passes it to `close` when the next identity replaces it or the
lifecycle handle closes it. The zero-argument helper remains available for
source compatibility and direct construction. A hosted root can read
`@Environment(\.innoDIContainerHostHandle)` to perform an explicit route,
document, or window close. Do not treat a temporary `onDisappear` as permanent
closure.

A `.shared` child belongs to its parent, which builds it during
initialization and returns that instance on every read. The host can present
it but cannot own it, so its hosted overload is `dashboardRootView(identity:)`
without a close hook: every identity shows the parent's one child, and the
host never closes it. The 7.0 `dashboardRootView(identity:close:)` spelling
still compiles and behaves as before, but is deprecated for a `.shared` child
because it hands the parent's instance to the hook at every identity change
and explicit close while the parent keeps serving it. Declare the child
`.transient` when each route, document, or window needs its own child that the
host closes.

## Previews

Swift type-checks the arguments of a file-scope macro such as
`#PreviewWithContainer` or `#Preview` before members that other macros
generate are visible to them. An argument that calls a `@DIContainer`
initializer, or a closure body that calls a generated feature-root helper,
therefore fails to compile, for example with `'AppContainer' cannot be
constructed because it has no accessible initializers`. The same declarations
compile inside ordinary functions, static members, and view bodies, so build
the container in a function and render generated helpers from a small wrapper
view:

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

// Generated initializers and helpers are called from ordinary declarations,
// never from the #PreviewWithContainer arguments themselves.
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

A static factory in an extension, such as `AppContainer.preview()`, works the
same way as the function. Write the macro at file scope in a library or app
source file; in `main.swift`, top-level code reads it as a statement.

See `Examples/PreviewInjectionExample/Sources/PreviewInjectionExample/PreviewInjectionExampleApp.swift`
for live, preview, and failure scenarios after migration.
