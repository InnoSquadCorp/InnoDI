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
/// > `_innoDIEnvironmentBridgeModifier()` directly. The underscore marks it
/// > as an InnoDI-internal requirement whose shape may evolve.
@MainActor
public protocol DIEnvironmentBridging {
    associatedtype InnoDIEnvironmentBridgeModifier: ViewModifier

    @_documentation(visibility: internal)
    func _innoDIEnvironmentBridgeModifier() -> InnoDIEnvironmentBridgeModifier
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
        modifier(container._innoDIEnvironmentBridgeModifier())
    }
}

@attached(member, names: named(_InnoDIEnvironmentBridgeModifier), named(_innoDIEnvironmentBridgeModifier))
@attached(extension, conformances: DIEnvironmentBridging)
/// Synthesizes SwiftUI environment wiring for a container type.
///
/// The attribute does not create `EnvironmentKey` / `EnvironmentValues`
/// declarations. Apps keep ownership of those keys and only describe how
/// container members should be forwarded at the root boundary.
/// Each `environment:` value must be a direct property key path rooted at
/// `EnvironmentValues` or `SwiftUI.EnvironmentValues`; aliases, other roots,
/// chained properties, and subscripts are rejected.
/// Targets with generic parameter packs are rejected in InnoDI 5.0; use
/// ordinary generic parameters or a non-generic adapter type.
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
