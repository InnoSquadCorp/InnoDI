//
//  Diagnostics.swift
//  InnoDIMacros
//

import SwiftDiagnostics
import SwiftSyntax

enum InnoDIDiagnosticCategory: String {
    case usage
    case validation
}

enum InnoDIDiagnosticCode: String {
    case provideSingleBinding = "provide.single-binding"
    case provideNamedPropertyRequired = "provide.named-property-required"
    case provideExplicitTypeRequired = "provide.explicit-type-required"
    case provideUnknownScope = "provide.unknown-scope"
    case provideSharedFactoryRequired = "provide.shared-factory-required"
    case provideTransientFactoryRequired = "provide.transient-factory-required"
    case provideInputInvalidConfiguration = "provide.input-invalid-configuration"
    case provideConcreteOptInRequired = "provide.concrete-opt-in-required"
    case provideFactoryConflict = "provide.factory-conflict"
    case provideAsyncFactoryInvalidScope = "provide.async-factory-invalid-scope"
    case provideAsyncFactoryMustBeAsync = "provide.async-factory-must-be-async"
    case provideLazyUnsupportedTarget = "provide.lazy-unsupported-target"
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
    case containerCustomInitUnsupported = "container.custom-init-unsupported"
    case containerOverridesNameConflict = "container.overrides-name-conflict"
    case graphDependencyCycle = "graph.dependency-cycle"
    case graphAmbiguousContainerReference = "graph.ambiguous-container-reference"
    case subScopeRequired = "sub.scope-required"
    case subUnknownScope = "sub.unknown-scope"
    case subConflictsWithProvide = "sub.conflicts-with-provide"
    case subUnknownParentMember = "sub.unknown-parent-member"
    case subSharedParentMustNotBeTransient = "sub.shared-parent-must-not-be-transient"

    var category: InnoDIDiagnosticCategory {
        switch self {
        case .provideSingleBinding, .provideNamedPropertyRequired, .provideExplicitTypeRequired,
                .provideUnknownScope, .provideInputInvalidConfiguration, .transientFactoryUnnamedParameters:
            return .usage
        case .provideSharedFactoryRequired, .provideTransientFactoryRequired, .provideConcreteOptInRequired,
                .provideFactoryConflict, .provideAsyncFactoryInvalidScope, .provideAsyncFactoryMustBeAsync,
                .provideLazyUnsupportedTarget, .provideProviderNonTransientTarget, .provideProviderUnsupportedTarget,
                .provideProviderEagerCall,
                .provideUnresolvedFactoryParameter, .provideUnavailableDependencyReference, .provideUnresolvedWithDependency,
                .containerUnknownDependency, .containerDependencyCycle, .containerMainActorConflict,
                .containerCustomInitUnsupported, .containerOverridesNameConflict, .graphDependencyCycle,
                .graphAmbiguousContainerReference,
                .subScopeRequired, .subUnknownScope, .subConflictsWithProvide,
                .subUnknownParentMember, .subSharedParentMustNotBeTransient:
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

    static func provideNamedPropertyRequired() -> Self {
        Self("@Provide requires a named property.", code: .provideNamedPropertyRequired)
    }

    static func provideExplicitTypeRequired() -> Self {
        Self("@Provide requires an explicit type.", code: .provideExplicitTypeRequired)
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
            "Concrete dependency '\(name): \(typeDescription)' requires concrete: true. Prefer protocol types when possible.",
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

    static func provideLazyUnsupportedTarget(memberName: String, dependencyName: String) -> Self {
        Self(
            "Factory parameter '\(dependencyName)' for '\(memberName)' cannot use Lazy<T> because '\(dependencyName)' is provided by asyncFactory and Lazy resolvers are synchronous.",
            code: .provideLazyUnsupportedTarget
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

    // MARK: - Phase M: @SubContainer diagnostics

    static func subScopeRequired(memberName: String) -> Self {
        Self(
            "@SubContainer on '\(memberName)' requires an explicit scope: argument — either .shared or .transient.",
            code: .subScopeRequired
        )
    }

    static func subUnknownScope(memberName: String, scopeName: String) -> Self {
        Self(
            "Unknown @SubContainer scope '.\(scopeName)' on '\(memberName)'. Valid scopes are .shared and .transient.",
            code: .subUnknownScope
        )
    }

    static func subConflictsWithProvide(memberName: String) -> Self {
        Self(
            "'\(memberName)' cannot carry both @Provide and @SubContainer. Remove one of the attributes — use @SubContainer for nested containers and @Provide for regular dependencies.",
            code: .subConflictsWithProvide
        )
    }

    static func subUnknownParentMember(memberName: String, parentMemberName: String) -> Self {
        Self(
            "@SubContainer on '\(memberName)' references parent member '\(parentMemberName)' via with:, but no such member exists. Only @Provide-annotated parent members can be passed to a child container.",
            code: .subUnknownParentMember
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
}
