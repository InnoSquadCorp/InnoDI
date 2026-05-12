//
//  InnoDISwiftUI.swift
//  InnoDISwiftUI
//

@_exported import InnoDI
@_exported import SwiftUI

/// Conformance synthesized by `@DIEnvironmentBridge`.
///
/// The generated witness returns a container-specific `ViewModifier` that
/// applies each configured `EnvironmentValues` key path in declaration order.
/// `InnoDISwiftUI` keeps the public root-boundary API generic so containers
/// do not need one-off modifier overloads.
///
/// > Important: Conforming types should always go through
/// > `@DIEnvironmentBridge` — application code should not implement
/// > `_innodiEnvironmentBridgeModifier()` directly. The underscore marks it
/// > as an InnoDI-internal requirement whose shape may evolve.
@MainActor
public protocol DIEnvironmentBridging {
    associatedtype InnoDIEnvironmentBridgeModifier: ViewModifier

    @_documentation(visibility: internal)
    func _innodiEnvironmentBridgeModifier() -> InnoDIEnvironmentBridgeModifier
}

public extension View {
    /// Applies the generated InnoDI environment bridge for `container`.
    @inlinable
    @MainActor
    func innodi<Container: DIEnvironmentBridging>(_ container: Container) -> some View {
        innodiServices(from: container)
    }

    /// Applies the generated InnoDI environment bridge for `container`.
    @inlinable
    @MainActor
    func innodiServices<Container: DIEnvironmentBridging>(from container: Container) -> some View {
        modifier(container._innodiEnvironmentBridgeModifier())
    }
}

@attached(member, names: named(_InnoDIEnvironmentBridgeModifier), named(_innodiEnvironmentBridgeModifier))
@attached(extension, conformances: DIEnvironmentBridging)
/// Synthesizes SwiftUI environment wiring for a container type.
///
/// The attribute does not create `EnvironmentKey` / `EnvironmentValues`
/// declarations. Apps keep ownership of those keys and only describe how
/// container members should be forwarded at the root boundary.
///
/// ```swift
/// @DIEnvironmentBridge([
///   (member: "greetingService", environment: \EnvironmentValues.greetingService),
///   (member: "activityService", environment: \EnvironmentValues.activityService),
/// ])
/// @DIContainer
/// struct AppContainer { ... }
/// ```
public macro DIEnvironmentBridge(
    _ mappings: [(member: String, environment: AnyKeyPath)]
) = #externalMacro(module: "InnoDIMacros", type: "DIEnvironmentBridgeMacro")

@available(*, deprecated, message: "Use @SubContainer(..., featureRoot:) or featureRoots: instead.")
@attached(peer, names: arbitrary)
/// Declares one SwiftUI feature-root helper for a `@SubContainer` property.
///
/// Repeat the attribute to attach multiple root views to the same child
/// container:
///
/// ```swift
/// @SubContainer(scope: .shared)
/// @DIFeatureRoot(DashboardFeatureRootView.self)
/// @DIFeatureRoot(DashboardShellView.self, as: "dashboardShell")
/// var dashboard: DashboardContainer
/// ```
///
/// This expands to `dashboardRootView()` and `dashboardShellRootView()` on the
/// parent container. The view type must declare `init(container: ChildType)`.
public macro DIFeatureRoot(
    _ rootView: Any.Type,
    as alias: String? = nil
) = #externalMacro(module: "InnoDIMacros", type: "DIFeatureRootMacro")

/// Wraps Xcode 16's `#Preview` so a SwiftUI preview can express a typed
/// container parameter once instead of constructing it, capturing it in a
/// `let`, and reading it back inside the trailing closure.
///
/// ```swift
/// #PreviewWithContainer(AppContainer(baseURL: "https://example.com")) { container in
///     container.dashboardRootView()
/// }
/// ```
///
/// The generated expansion always wraps a `#Preview` macro, so all of
/// Xcode's preview features (timing, traits, multiple previews per file)
/// remain available; the InnoDI helper only removes the boilerplate of
/// referring to the same container twice.
@freestanding(expression)
public macro PreviewWithContainer<Container, Result>(
    _ container: @autoclosure () -> Container,
    _ body: (Container) -> Result
) -> Result = #externalMacro(module: "InnoDIMacros", type: "PreviewWithContainerMacro")
