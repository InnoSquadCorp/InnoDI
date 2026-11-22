import Testing

import InnoDI

// Generated code shares scopes with user-written type spellings and with
// member-named initializer parameters. Each fixture below compiles only while
// the generated generic parameters and local bindings stay in the reserved
// `_InnoDI` / `_innoDI` namespace, or while a peer declaration spells nested
// types through the container.

// MARK: - withOverrides generic parameter

fileprivate enum OperationResult: Equatable {
    case success
    case failure
}

@DIContainer
fileprivate struct OperationResultInputContainer {
    @Input var last: OperationResult
    @Provide(.shared, factory: { (last: OperationResult) in last == .success })
    var succeeded: Bool
}

fileprivate enum OperationResultNamespace {
    enum OperationResult {
        case pending
    }

    @DIContainer
    struct NestedContainer {
        @Input var last: OperationResult
    }
}

// MARK: - Transient sub-container override binding

@DIContainer
fileprivate struct ApplyNamedChild {
    @Input var apply: Int
    @Input var direct: Int
    @Provide(.shared, factory: { (apply: Int, direct: Int) in apply * 10 + direct })
    var combined: Int
}

@DIContainer
fileprivate struct ApplyNamedParent {
    @Input var apply: Int
    @Input var direct: Int

    @SubContainer(scope: .transient, with: [\Self.apply, \Self.direct])
    var transientChild: ApplyNamedChild

    @SubContainer(scope: .shared, with: [\Self.apply, \Self.direct])
    var sharedChild: ApplyNamedChild
}

// MARK: - Override slots beside DIOverrideEffectValidating requirements

@DIContainer
fileprivate struct EffectRequirementNeighbors {
    @Provide(.shared, effect: .sideEffect, factory: 1) var requiredEffectOverrides: Int
    @Provide(.shared, effect: .sideEffect, factory: 2) var missing: Int
    @Provide(.shared, effect: .sideEffect, factory: 3) var set: Int
    @Provide(.shared, effect: .sideEffect, factory: 4) var useDefault: Int
}

// MARK: - Component dependency protocol outside the container body

@DIContainerRole(role: ContainerRole.component)
struct NestedTypeInputComponent {
    enum Mode: Hashable, Sendable {
        case automatic
        case manual
    }

    struct Settings: Equatable {
        let level: Int
    }

    typealias ModeHandler = (Mode) -> Void

    @Input var mode: Mode
    @Input var optionalMode: Mode?
    @Input var modes: [Mode]
    @Input var settingsByMode: [Mode: Settings]
    @Input var onChange: (Mode) -> Void
    @Input(escaping: true) var handler: ModeHandler
    @Input var selfMode: Self.Mode
    @Input var label: String
}

private struct NestedTypeInputDependencies: NestedTypeInputComponentDependencies {
    var mode: NestedTypeInputComponent.Mode
    var optionalMode: NestedTypeInputComponent.Mode?
    var modes: [NestedTypeInputComponent.Mode]
    var settingsByMode: [NestedTypeInputComponent.Mode: NestedTypeInputComponent.Settings]
    var onChange: (NestedTypeInputComponent.Mode) -> Void
    var handler: NestedTypeInputComponent.ModeHandler
    var selfMode: NestedTypeInputComponent.Mode
    var label: String
}

enum NestedTypeComponentNamespace {
    @DIContainerRole(role: ContainerRole.component)
    struct InnerComponent {
        enum Kind {
            case primary
        }

        @Input var kind: Kind
    }

    struct InnerDependencies: InnerComponentDependencies {
        var kind: InnerComponent.Kind
    }
}

@Suite("Generated names stay out of user scopes")
struct GeneratedNameScopeRuntimeTests {
    @Test("A user type named OperationResult is not shadowed by withOverrides")
    func operationResultInputCompiles() async throws {
        let sync = OperationResultInputContainer.withOverrides(last: .success) { _ in } operation: { container in
            container.last
        }
        let asyncThrows = try await OperationResultInputContainer.withOverrides(last: .failure) { _ in } operation: { container async throws in
            container.succeeded
        }
        #expect(sync == .success)
        #expect(asyncThrows == false)
        #expect(OperationResultNamespace.NestedContainer(last: .pending).last == .pending)
    }

    @Test("Parent inputs named apply and direct reach a transient child")
    func applyNamedInputsReachTransientChild() {
        let parent = ApplyNamedParent(apply: 7, direct: 2)
        #expect(parent.transientChild.apply == 7)
        #expect(parent.transientChild.combined == 72)
        #expect(parent.sharedChild.combined == 72)

        let overridden = ApplyNamedParent(apply: 7, direct: 2) {
            $0.transientChildOverrides = { $0.combined = 99 }
            $0.sharedChildOverrides = { $0.combined = 98 }
        }
        #expect(overridden.transientChild.apply == 7)
        #expect(overridden.transientChild.direct == 2)
        #expect(overridden.transientChild.combined == 99)
        #expect(overridden.sharedChild.apply == 7)
        #expect(overridden.sharedChild.combined == 98)
    }

    @Test("Providers named after effect-validation neighbors keep their slots")
    func effectRequirementNeighborsKeepSlots() {
        #expect(EffectRequirementNeighbors.Overrides.requiredEffectOverrides.count == 4)
        var overrides = EffectRequirementNeighbors.Overrides()
        #expect(overrides.missingEffectOverrides.map(\.providerName).sorted()
            == ["missing", "requiredEffectOverrides", "set", "useDefault"])
        overrides.set(\.missing, to: 20)
        overrides.requiredEffectOverrides = 10
        overrides.set = 30
        overrides.useDefault = 40
        #expect(overrides.missingEffectOverrides.isEmpty)

        let container = EffectRequirementNeighbors {
            $0.set(\.missing, to: 20)
            $0.useDefault(\.missing)
            $0.set = 30
        }
        #expect(container.missing == 2)
        #expect(container.set == 30)
        #expect(container.requiredEffectOverrides == 1)
        #expect(container.useDefault == 4)
    }

    @Test("A component's dependency protocol names the container's nested types")
    func componentNestedInputTypesResolve() {
        let component = NestedTypeInputComponent(
            dependencies: NestedTypeInputDependencies(
                mode: .manual,
                optionalMode: nil,
                modes: [.automatic, .manual],
                settingsByMode: [.manual: .init(level: 3)],
                onChange: { _ in },
                handler: { _ in },
                selfMode: .automatic,
                label: "nested"
            )
        )
        #expect(component.mode == .manual)
        #expect(component.optionalMode == nil)
        #expect(component.modes == [.automatic, .manual])
        #expect(component.settingsByMode[.manual]?.level == 3)
        #expect(component.selfMode == .automatic)
        #expect(component.label == "nested")

        let inner = NestedTypeComponentNamespace.InnerComponent(
            dependencies: NestedTypeComponentNamespace.InnerDependencies(kind: .primary)
        )
        #expect(inner.kind == .primary)
    }
}
