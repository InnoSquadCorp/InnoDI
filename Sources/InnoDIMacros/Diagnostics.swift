//
//  Diagnostics.swift
//  InnoDIMacros
//
//  User-facing diagnostic messages emitted by the InnoDI macros. Every code
//  is also described in the DocC `DiagnosticsGuide` article
//  (Sources/InnoDI/InnoDI.docc/DiagnosticsGuide.md) — keep the two in sync
//  when adding or renaming a case so that tools surfacing the diagnostic
//  ID can link to documentation.
//

import InnoDICore
import SwiftDiagnostics
import SwiftSyntax

enum InnoDIDiagnosticCategory: String {
    case usage
    case validation
}

enum InnoDIDiagnosticCode: String, CaseIterable {
    case provideSingleBinding = "provide.single-binding"
    case provideNamedPropertyRequired = "provide.named-property-required"
    case provideExplicitTypeRequired = "provide.explicit-type-required"
    case subSingleBinding = "sub.single-binding"
    case subNamedPropertyRequired = "sub.named-property-required"
    case subExplicitTypeRequired = "sub.explicit-type-required"
    case provideUnknownScope = "provide.unknown-scope"
    case provideSharedFactoryRequired = "provide.shared-factory-required"
    case provideTransientFactoryRequired = "provide.transient-factory-required"
    case provideInputInvalidConfiguration = "provide.input-invalid-configuration"
    case provideConcreteOptInRequired = "provide.concrete-opt-in-required"
    case provideFactoryConflict = "provide.factory-conflict"
    case provideAsyncFactoryInvalidScope = "provide.async-factory-invalid-scope"
    case provideAsyncFactoryMustBeAsync = "provide.async-factory-must-be-async"
    case provideFactoryMustBeSync = "provide.factory-must-be-sync"
    case provideFactoryMustNotThrow = "provide.factory-must-not-throw"
    case provideBoolLiteralRequired = "provide.bool-literal-required"
    case provideInvalidWithDependencies = "provide.invalid-with-dependencies"
    case provideLazyUnsupportedTarget = "provide.lazy-unsupported-target"
    case provideLazyEagerCall = "provide.lazy-eager-call"
    case provideProviderNonTransientTarget = "provide.provider-non-transient-target"
    case provideProviderUnsupportedTarget = "provide.provider-unsupported-target"
    case provideProviderEagerCall = "provide.provider-eager-call"
    case provideUnresolvedFactoryParameter = "provide.unresolved-factory-parameter"
    case provideUnavailableDependencyReference = "provide.unavailable-dependency-reference"
    case provideUnresolvedWithDependency = "provide.unresolved-with-dependency"
    case transientFactoryUnnamedParameters = "transient-factory.unnamed-parameters"
    case containerUnknownDependency = "container.unknown-dependency"
    case containerDependencyCycle = "container.dependency-cycle"
    case containerMainActorConflict = "container.mainactor-conflict"
    case containerBoolLiteralRequired = "container.bool-literal-required"
    case containerCustomInitUnsupported = "container.custom-init-unsupported"
    case containerOverridesNameConflict = "container.overrides-name-conflict"
    case containerReservedNamePrefix = "container.reserved-name-prefix"
    case graphDependencyCycle = "graph.dependency-cycle"
    case graphAmbiguousContainerReference = "graph.ambiguous-container-reference"
    case subScopeRequired = "sub.scope-required"
    case subUnknownScope = "sub.unknown-scope"
    case subConflictsWithProvide = "sub.conflicts-with-provide"
    case subOverridesNameConflict = "sub.overrides-name-conflict"
    case subUnknownParentMember = "sub.unknown-parent-member"
    case subBindingsConflictsWithWith = "sub.bindings-conflicts-with-with"
    case subInvalidSameNameWiring = "sub.invalid-same-name-wiring"
    case subInvalidBindings = "sub.invalid-bindings"
    case subDuplicateChildBinding = "sub.duplicate-child-binding"
    case subUnknownChildInput = "sub.unknown-child-input"
    case subAutoWiringAmbiguous = "sub.auto-wiring-ambiguous"
    case subSharedParentMustNotBeTransient = "sub.shared-parent-must-not-be-transient"
    case provideLazyAliased = "provide.lazy-aliased"
    case provideProviderAliased = "provide.provider-aliased"
    case swiftUIFeatureRootWithoutSubContainer = "swiftui.feature-root-without-subcontainer"
    case swiftUIFeatureRootDuplicateDefault = "swiftui.feature-root-duplicate-default"
    case swiftUIFeatureRootHelperNameConflict = "swiftui.feature-root-helper-name-conflict"
    case swiftUIFeatureRootInvalidAlias = "swiftui.feature-root-invalid-alias"
    case swiftUIFeatureRootInvalidRoot = "swiftui.feature-root-invalid-root"
    case swiftUIEnvironmentBridgeUnknownMember = "swiftui.environment-bridge-unknown-member"
    case swiftUIEnvironmentBridgeDuplicateMember = "swiftui.environment-bridge-duplicate-member"
    case swiftUIEnvironmentBridgeAsyncMember = "swiftui.environment-bridge-async-member"
    case swiftUIEnvironmentBridgeInvalidKeyPath = "swiftui.environment-bridge-invalid-keypath"
    case swiftUIEnvironmentBridgeInvalidArguments = "swiftui.environment-bridge-invalid-arguments"
    case componentRequiresContainer = "component.requires-container"
    case componentOverridesBuilderRequired = "component.overrides-builder-required"
    case hierarchyRootRequiresContainer = "hierarchy-root.requires-container"
    case previewWithContainerMissingContainerExpression = "swiftui.preview-with-container-missing-container"
    case previewWithContainerMissingTrailingClosure = "swiftui.preview-with-container-missing-closure"
    case previewWithContainerMissingContainerParameter = "swiftui.preview-with-container-missing-parameter"
    case generateMockRequiresProtocol = "mock.requires-protocol"
    case generateMockExperimentalSkeleton = "mock.experimental-skeleton"
    case generateMockUnsupportedMember = "mock.unsupported-member"
    case internalCodegenInvariant = "internal.codegen-invariant"

    var category: InnoDIDiagnosticCategory {
        switch self {
        case .provideSingleBinding, .provideNamedPropertyRequired, .provideExplicitTypeRequired,
                .subSingleBinding, .subNamedPropertyRequired, .subExplicitTypeRequired,
                .provideUnknownScope, .provideInputInvalidConfiguration, .transientFactoryUnnamedParameters:
            return .usage
        case .provideSharedFactoryRequired, .provideTransientFactoryRequired, .provideConcreteOptInRequired,
                .provideFactoryConflict, .provideAsyncFactoryInvalidScope, .provideAsyncFactoryMustBeAsync,
                .provideFactoryMustBeSync, .provideFactoryMustNotThrow,
                .provideBoolLiteralRequired, .provideInvalidWithDependencies,
                .provideLazyUnsupportedTarget, .provideLazyEagerCall,
                .provideProviderNonTransientTarget, .provideProviderUnsupportedTarget, .provideProviderEagerCall,
                .provideUnresolvedFactoryParameter, .provideUnavailableDependencyReference, .provideUnresolvedWithDependency,
                .containerUnknownDependency, .containerDependencyCycle, .containerMainActorConflict,
                .containerBoolLiteralRequired,
                .containerCustomInitUnsupported, .containerOverridesNameConflict,
                .containerReservedNamePrefix, .graphDependencyCycle,
                .graphAmbiguousContainerReference,
                .subScopeRequired, .subUnknownScope, .subConflictsWithProvide, .subOverridesNameConflict,
                .subUnknownParentMember, .subBindingsConflictsWithWith,
                .subInvalidSameNameWiring, .subInvalidBindings,
                .subDuplicateChildBinding, .subUnknownChildInput, .subAutoWiringAmbiguous,
                .subSharedParentMustNotBeTransient,
                .provideLazyAliased, .provideProviderAliased,
                .swiftUIFeatureRootWithoutSubContainer, .swiftUIFeatureRootDuplicateDefault,
                .swiftUIFeatureRootInvalidAlias, .swiftUIFeatureRootInvalidRoot,
                .swiftUIFeatureRootHelperNameConflict, .swiftUIEnvironmentBridgeUnknownMember,
                .swiftUIEnvironmentBridgeDuplicateMember, .swiftUIEnvironmentBridgeAsyncMember,
                .swiftUIEnvironmentBridgeInvalidKeyPath,
                .swiftUIEnvironmentBridgeInvalidArguments,
                .componentRequiresContainer, .componentOverridesBuilderRequired,
                .hierarchyRootRequiresContainer,
                .previewWithContainerMissingContainerExpression,
                .previewWithContainerMissingTrailingClosure,
                .previewWithContainerMissingContainerParameter,
                .generateMockRequiresProtocol,
                .generateMockExperimentalSkeleton,
                .generateMockUnsupportedMember,
                .internalCodegenInvariant:
            return .validation
        }
    }
}

extension InnoDIDiagnosticCode {
    var messageID: MessageID {
        MessageID(domain: "InnoDI.\(category.rawValue)", id: rawValue)
    }
}

struct SimpleDiagnostic: DiagnosticMessage {
    let message: String
    let code: InnoDIDiagnosticCode
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(_ message: String, code: InnoDIDiagnosticCode, severity: DiagnosticSeverity = .error) {
        self.message = message
        self.code = code
        self.diagnosticID = code.messageID
        self.severity = severity
    }
}

struct SimpleNote: NoteMessage {
    let message: String
    let noteID: MessageID

    init(_ message: String, code: InnoDIDiagnosticCode, suffix: String) {
        self.message = message
        self.noteID = MessageID(domain: "InnoDI.\(code.category.rawValue)", id: "\(code.rawValue).note.\(suffix)")
    }
}

struct SimpleFixIt: FixItMessage {
    static let addConcreteTrueTitle = "Add concrete: true"

    let message: String
    let fixItID: MessageID

    init(_ message: String, code: InnoDIDiagnosticCode, suffix: String) {
        self.message = message
        self.fixItID = MessageID(domain: "InnoDI.\(code.category.rawValue)", id: "\(code.rawValue).fixit.\(suffix)")
    }
}

extension SimpleDiagnostic {
    static func provideSingleBinding() -> Self {
        Self("@Provide supports a single variable binding.", code: .provideSingleBinding)
    }

    static func subSingleBinding() -> Self {
        Self("@SubContainer supports a single variable binding.", code: .subSingleBinding)
    }

    static func provideNamedPropertyRequired() -> Self {
        Self("@Provide requires a named property.", code: .provideNamedPropertyRequired)
    }

    static func subNamedPropertyRequired() -> Self {
        Self("@SubContainer requires a named property.", code: .subNamedPropertyRequired)
    }

    static func provideExplicitTypeRequired() -> Self {
        Self("@Provide requires an explicit type.", code: .provideExplicitTypeRequired)
    }

    static func subExplicitTypeRequired() -> Self {
        Self("@SubContainer requires an explicit type.", code: .subExplicitTypeRequired)
    }

    static func provideUnknownScope(_ name: String) -> Self {
        Self("Unknown @Provide scope: \(name).", code: .provideUnknownScope)
    }

    static func provideSharedFactoryRequired() -> Self {
        Self(
            "@Provide(.shared) requires factory: <expr>, type: Type.self, or property initializer.",
            code: .provideSharedFactoryRequired
        )
    }

    static func provideTransientFactoryRequired() -> Self {
        Self(
            "@Provide(.transient) requires factory: <expr>, type: Type.self, or property initializer.",
            code: .provideTransientFactoryRequired
        )
    }

    static func provideInputInvalidConfiguration() -> Self {
        Self(
            "@Provide(.input) should not include a factory, type, or initializer.",
            code: .provideInputInvalidConfiguration
        )
    }

    static func provideConcreteOptInRequired(name: String, typeDescription: String) -> Self {
        Self(
            "Concrete dependency '\(name): \(typeDescription)' requires concrete: true.",
            code: .provideConcreteOptInRequired
        )
    }

    static func provideFactoryConflict() -> Self {
        Self(
            "@Provide cannot include both factory: and asyncFactory: at the same time.",
            code: .provideFactoryConflict
        )
    }

    static func provideAsyncFactoryInvalidScope() -> Self {
        Self(
            "@Provide(.input) should not include asyncFactory.",
            code: .provideAsyncFactoryInvalidScope
        )
    }

    static func provideAsyncFactoryMustBeAsync() -> Self {
        Self(
            "asyncFactory must be an async closure expression.",
            code: .provideAsyncFactoryMustBeAsync
        )
    }

    static func provideFactoryMustBeSync(memberName: String) -> Self {
        Self(
            "factory: for '\(memberName)' must be synchronous. Use asyncFactory: for async construction.",
            code: .provideFactoryMustBeSync
        )
    }

    static func provideFactoryMustNotThrow(memberName: String) -> Self {
        Self(
            "factory: for '\(memberName)' must be non-throwing. Handle errors inside the factory or use asyncFactory: when asynchronous throwing construction is required.",
            code: .provideFactoryMustNotThrow
        )
    }

    static func provideBoolLiteralRequired(label: String) -> Self {
        Self(
            "@Provide \(label): requires a literal true or false. Macros cannot evaluate arbitrary Bool expressions.",
            code: .provideBoolLiteralRequired
        )
    }

    static func provideInvalidWithDependencies(memberName: String) -> Self {
        Self(
            "@Provide for '\(memberName)' requires with: to be a literal key-path array such as [\\.config] or [].",
            code: .provideInvalidWithDependencies
        )
    }

    static func provideLazyUnsupportedTarget(memberName: String, dependencyName: String) -> Self {
        Self(
            "Factory parameter '\(dependencyName)' for '\(memberName)' cannot use Lazy<T> because '\(dependencyName)' is provided by asyncFactory and Lazy resolvers are synchronous.",
            code: .provideLazyUnsupportedTarget
        )
    }

    static func provideLazyEagerCall(memberName: String, dependencyName: String) -> Self {
        Self(
            "Factory parameter '\(dependencyName)' for '\(memberName)' cannot call Lazy<T> during .shared construction. Store or forward the lazy handle and invoke it only after the container has finished initializing.",
            code: .provideLazyEagerCall
        )
    }

    static func provideProviderNonTransientTarget(memberName: String, dependencyName: String, targetScope: ProvideScope) -> Self {
        Self(
            "Factory parameter '\(dependencyName)' for '\(memberName)' cannot use Provider<T> because '\(dependencyName)' has scope .\(targetScope.rawValue). Provider<T> re-enters a .transient accessor on each call, but overrides may still return stored values, so it requires a .transient target.",
            code: .provideProviderNonTransientTarget
        )
    }

    static func provideProviderUnsupportedTarget(memberName: String, dependencyName: String) -> Self {
        Self(
            "Factory parameter '\(dependencyName)' for '\(memberName)' cannot use Provider<T> because '\(dependencyName)' is produced by asyncFactory. Provider<T> only supports synchronous .transient targets; use an async-aware handle instead.",
            code: .provideProviderUnsupportedTarget
        )
    }

    static func provideProviderEagerCall(memberName: String, dependencyName: String) -> Self {
        Self(
            "Factory parameter '\(dependencyName)' for '\(memberName)' cannot call Provider<T> during .shared construction. Store or forward the provider and invoke it only after the container has finished initializing.",
            code: .provideProviderEagerCall
        )
    }

    static func swiftUIFeatureRootWithoutSubContainer() -> Self {
        Self(
            "@DIFeatureRoot can only be attached to a property that also declares @SubContainer.",
            code: .swiftUIFeatureRootWithoutSubContainer
        )
    }

    static func swiftUIFeatureRootDuplicateDefault(propertyName: String) -> Self {
        Self(
            "Property '\(propertyName)' can declare at most one default @DIFeatureRoot without an alias.",
            code: .swiftUIFeatureRootDuplicateDefault
        )
    }

    static func swiftUIFeatureRootHelperNameConflict(helperName: String) -> Self {
        Self(
            "Generated SwiftUI helper '\(helperName)' would conflict with an existing member or another @DIFeatureRoot helper.",
            code: .swiftUIFeatureRootHelperNameConflict
        )
    }

    static func swiftUIFeatureRootInvalidAlias(alias: String) -> Self {
        Self(
            "Alias '\(alias)' for @DIFeatureRoot must be a non-empty Swift identifier.",
            code: .swiftUIFeatureRootInvalidAlias
        )
    }

    static func swiftUIFeatureRootInvalidRoot() -> Self {
        Self(
            "Feature root declarations must use a root view type expression such as `FeatureRootView.self` or `FeatureRoot(FeatureRootView.self)`.",
            code: .swiftUIFeatureRootInvalidRoot
        )
    }

    static func swiftUIEnvironmentBridgeUnknownMember(memberName: String) -> Self {
        Self(
            "@DIEnvironmentBridge references unknown container member '\(memberName)'.",
            code: .swiftUIEnvironmentBridgeUnknownMember
        )
    }

    static func swiftUIEnvironmentBridgeDuplicateMember(memberName: String) -> Self {
        Self(
            "@DIEnvironmentBridge maps container member '\(memberName)' more than once.",
            code: .swiftUIEnvironmentBridgeDuplicateMember
        )
    }

    static func swiftUIEnvironmentBridgeAsyncMember(memberName: String) -> Self {
        Self(
            "@DIEnvironmentBridge cannot map async container member '\(memberName)' into SwiftUI EnvironmentValues. Expose a synchronous value or inject a service that performs async work internally.",
            code: .swiftUIEnvironmentBridgeAsyncMember
        )
    }

    static func swiftUIEnvironmentBridgeInvalidKeyPath(label: String) -> Self {
        let message: String
        if label == "member" {
            message = "@DIEnvironmentBridge requires 'member' to be a string literal naming a container member."
        } else {
            message = "@DIEnvironmentBridge requires '\(label)' to be a key-path expression."
        }
        return Self(message, code: .swiftUIEnvironmentBridgeInvalidKeyPath)
    }

    static func swiftUIEnvironmentBridgeInvalidArguments() -> Self {
        Self(
            "@DIEnvironmentBridge requires a single array literal of (member: ..., environment: ...) mappings.",
            code: .swiftUIEnvironmentBridgeInvalidArguments
        )
    }

    static func componentRequiresContainer() -> Self {
        Self(
            "@DIComponent can only be attached to a type that also declares @DIContainer.",
            code: .componentRequiresContainer
        )
    }

    static func componentOverridesBuilderRequired() -> Self {
        Self(
            "@DIComponent requires the synthesized Overrides builder from @DIContainer. Remove the user-defined Overrides type or remove @DIComponent.",
            code: .componentOverridesBuilderRequired
        )
    }

    static func hierarchyRootRequiresContainer() -> Self {
        Self(
            "@DIHierarchyRoot can only be attached to a type that also declares @DIContainer.",
            code: .hierarchyRootRequiresContainer
        )
    }

    static func provideUnresolvedFactoryParameter(memberName: String, parameterName: String) -> Self {
        Self(
            "Factory parameter '\(parameterName)' for '\(memberName)' does not match any injectable container member.",
            code: .provideUnresolvedFactoryParameter
        )
    }

    static func provideUnavailableDependencyReference(memberName: String, dependencyName: String) -> Self {
        Self(
            "Dependency '\(dependencyName)' referenced by '\(memberName)' is not available in this declaration order or scope.",
            code: .provideUnavailableDependencyReference
        )
    }

    static func provideUnresolvedWithDependency(memberName: String, dependencyName: String) -> Self {
        Self(
            "Dependency '\(dependencyName)' in with: for '\(memberName)' does not match any injectable container member.",
            code: .provideUnresolvedWithDependency
        )
    }

    static func transientFactoryUnnamedParameters() -> Self {
        Self(
            "Factory closure parameters must be named for injection.",
            code: .transientFactoryUnnamedParameters
        )
    }

    static func containerUnknownDependency(dependencyName: String, memberName: String) -> Self {
        Self(
            "Unknown dependency '\(dependencyName)' referenced by '\(memberName)'.",
            code: .containerUnknownDependency
        )
    }

    static func containerDependencyCycle(path: String) -> Self {
        Self(
            "Dependency cycle detected in container: \(path). To break this cycle without restructuring, wrap one factory parameter in Lazy<T>.",
            code: .containerDependencyCycle
        )
    }

    static func containerMainActorConflict(actorName: String) -> Self {
        Self(
            "mainActor: true conflicts with existing global actor '@\(actorName)'.",
            code: .containerMainActorConflict
        )
    }

    static func containerBoolLiteralRequired(label: String) -> Self {
        Self(
            "@DIContainer \(label): requires a literal true or false. Use conditional compilation to choose different attribute spellings per build configuration.",
            code: .containerBoolLiteralRequired
        )
    }

    static func containerCustomInitUnsupported() -> Self {
        Self(
            "@DIContainer does not support user-defined init declarations in the annotated type or any extension. Remove the custom init and use the synthesized initializer, or switch to manual wiring.",
            code: .containerCustomInitUnsupported
        )
    }

    static func containerOverridesNameConflict(kind: String) -> Self {
        Self(
            "A nested 'Overrides' \(kind) is already declared. InnoDI's @DIContainer would normally generate an Overrides builder, but the user declaration takes precedence. Rename the user type or skip InnoDI's override scaffolding.",
            code: .containerOverridesNameConflict,
            severity: .warning
        )
    }

    // MARK: - @SubContainer diagnostics

    static func subScopeRequired(memberName: String) -> Self {
        Self(
            "@SubContainer on '\(memberName)' requires an explicit scope: argument — either .shared or .transient.",
            code: .subScopeRequired
        )
    }

    static func subUnknownScope(memberName: String, scopeName: String) -> Self {
        Self(
            "Unknown @SubContainer scope '\(scopeName)' on '\(memberName)'. Valid scopes are .shared and .transient.",
            code: .subUnknownScope
        )
    }

    static func subConflictsWithProvide(memberName: String) -> Self {
        Self(
            "'\(memberName)' cannot carry both @Provide and @SubContainer. Remove one of the attributes — use @SubContainer for nested containers and @Provide for regular dependencies.",
            code: .subConflictsWithProvide
        )
    }

    static func subOverridesNameConflict(memberName: String, generatedName: String) -> Self {
        Self(
            "@SubContainer on '\(memberName)' would generate an override slot named '\(generatedName)', but that name is already used by another container member. Rename '\(memberName)' or the conflicting member so InnoDI can synthesize the child override API.",
            code: .subOverridesNameConflict
        )
    }

    static func subUnknownParentMember(memberName: String, parentMemberName: String) -> Self {
        Self(
            "@SubContainer on '\(memberName)' references parent member '\(parentMemberName)' via with:, but no such member exists. Only @Provide-annotated parent members can be passed to a child container.",
            code: .subUnknownParentMember
        )
    }

    static func subBindingsConflictsWithWith(memberName: String) -> Self {
        Self(
            "@SubContainer on '\(memberName)' cannot use with: together with bindings:. Use with: for same-name subset/reorder wiring, or bindings: for explicit child-to-parent remapping.",
            code: .subBindingsConflictsWithWith
        )
    }

    static func subInvalidSameNameWiring(
        memberName: String,
        label: SubContainerSameNameWiringLabel
    ) -> Self {
        switch label {
        case .with:
            return Self(
                "@SubContainer on '\(memberName)' requires with: to be a literal array of key paths, such as with: [\\.config] or with: [] for an explicit empty subset. Runtime variables and computed elements are not supported.",
                code: .subInvalidSameNameWiring
            )
        }
    }

    static func subInvalidBindings(memberName: String) -> Self {
        Self(
            "@SubContainer on '\(memberName)' requires bindings: to be a literal array of (child:parent:) key-path tuples.",
            code: .subInvalidBindings
        )
    }

    static func subDuplicateChildBinding(memberName: String, childInputName: String) -> Self {
        Self(
            "@SubContainer on '\(memberName)' binds child input '\(childInputName)' more than once in bindings:. Each child input can appear at most once.",
            code: .subDuplicateChildBinding
        )
    }

    static func subUnknownChildInput(
        memberName: String,
        childInputName: String,
        childContainerName: String
    ) -> Self {
        Self(
            "@SubContainer on '\(memberName)' binds child input '\(childInputName)', but '\(childContainerName)' does not declare a matching .input member.",
            code: .subUnknownChildInput
        )
    }

    static func subAutoWiringAmbiguous(memberName: String) -> Self {
        Self(
            "@SubContainer on '\(memberName)' cannot infer child inputs because the parent has multiple @Provide members. Add with: for same-name wiring, or bindings: for explicit child-to-parent remapping. Use with: [] when the child is intentionally constructed without parent inputs.",
            code: .subAutoWiringAmbiguous
        )
    }

    static func containerReservedNamePrefix(memberName: String, reservedPrefix: String) -> Self {
        Self(
            "Container member '\(memberName)' uses the reserved prefix '\(reservedPrefix)'. InnoDI synthesizes private storage with this prefix and a user-declared member would collide with the generated symbols. Rename '\(memberName)' so it does not start with '\(reservedPrefix)'.",
            code: .containerReservedNamePrefix
        )
    }

    static func subSharedParentMustNotBeTransient(
        memberName: String,
        parentMemberName: String
    ) -> Self {
        Self(
            "@SubContainer(scope: .shared) '\(memberName)' cannot read parent member '\(parentMemberName)' because it has .transient scope — the child is built inside init where transient accessors are not yet callable. Use @SubContainer(scope: .transient) instead, or restructure the parent so '\(parentMemberName)' is .shared or .input.",
            code: .subSharedParentMustNotBeTransient
        )
    }

    static func provideLazyAliased(
        parameterName: String,
        aliasName: String
    ) -> Self {
        Self(
            "Spell 'Lazy<T>' (or 'InnoDI.Lazy<T>') directly — the macro cannot follow typealiases, so parameter '\(parameterName)' typed '\(aliasName)' is treated as a hard edge and participates in cycle detection.",
            code: .provideLazyAliased,
            severity: .warning
        )
    }

    static func provideProviderAliased(
        parameterName: String,
        aliasName: String
    ) -> Self {
        Self(
            "Spell 'Provider<T>' (or 'InnoDI.Provider<T>') directly — the macro cannot follow typealiases, so parameter '\(parameterName)' typed '\(aliasName)' is treated as a hard edge and loses the '.transient'-target rule plus the cycle-detection exemption.",
            code: .provideProviderAliased,
            severity: .warning
        )
    }

    // MARK: - Internal invariant violations
    //
    // These fire only if a codegen helper encountered a case the validator
    // was supposed to reject first. They are reported as diagnostics
    // (instead of `fatalError`) so the compiler plugin degrades gracefully
    // — the user sees a clear "please file a bug" message rather than an
    // anonymous macro crash. Each message includes the original internal
    // description so issue reports are actionable.
    static func internalCodegenInvariant(description: String) -> Self {
        Self(
            "InnoDI internal codegen invariant violated: \(description). This should have been caught by validation — please file a bug at https://github.com/InnoSquadCorp/InnoDI/issues.",
            code: .internalCodegenInvariant
        )
    }

    static func previewWithContainerMissingContainerExpression() -> Self {
        Self(
            "#PreviewWithContainer requires a container expression as its first argument, e.g. `#PreviewWithContainer(AppContainer(baseURL: \"...\")) { container in ... }`.",
            code: .previewWithContainerMissingContainerExpression
        )
    }

    static func previewWithContainerMissingTrailingClosure() -> Self {
        Self(
            "#PreviewWithContainer requires a closure with a single container parameter, e.g. `{ container in container.featureRootView() }`.",
            code: .previewWithContainerMissingTrailingClosure
        )
    }

    static func previewWithContainerMissingContainerParameter() -> Self {
        Self(
            "#PreviewWithContainer requires the preview closure to declare one container parameter, e.g. `{ container in container.featureRootView() }`. Use #Preview directly when the body does not need the container.",
            code: .previewWithContainerMissingContainerParameter
        )
    }

    static func generateMockRequiresProtocol() -> Self {
        Self(
            "@GenerateMock can only be attached to a protocol declaration. See docs/rfcs/0001-macro-mock-generation.md for the supported attachment sites.",
            code: .generateMockRequiresProtocol
        )
    }

    static func generateMockExperimentalSkeleton(protocolName: String) -> Self {
        Self(
            "@GenerateMock attached to '\(protocolName)' found no mockable members; the generated mock contains only the RFC 0001 skeleton.",
            code: .generateMockExperimentalSkeleton,
            severity: .note
        )
    }

    static func generateMockUnsupportedMember(memberNames: [String]) -> Self {
        let listed = memberNames.prefix(5).joined(separator: ", ")
        let suffix = memberNames.count > 5 ? " (+\(memberNames.count - 5) more)" : ""
        return Self(
            "@GenerateMock cannot synthesize this protocol because one or more requirements or protocol features are unsupported: \(listed)\(suffix). Associated types, Sendable inheritance, static/class requirements, subscripts, rethrows or typed throws, inout parameters, and opaque return types need a hand-written mock until the RFC 0001 support matrix expands.",
            code: .generateMockUnsupportedMember,
            severity: .warning
        )
    }
}
