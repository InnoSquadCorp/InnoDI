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
    case provideUnresolvedFactoryParameter = "provide.unresolved-factory-parameter"
    case provideUnavailableDependencyReference = "provide.unavailable-dependency-reference"
    case provideUnresolvedWithDependency = "provide.unresolved-with-dependency"
    case transientFactoryUnnamedParameters = "transient-factory.unnamed-parameters"
    case containerUnknownDependency = "container.unknown-dependency"
    case containerDependencyCycle = "container.dependency-cycle"
    case containerMainActorConflict = "container.mainactor-conflict"
    case containerCustomInitUnsupported = "container.custom-init-unsupported"
    case graphDependencyCycle = "graph.dependency-cycle"
    case graphAmbiguousContainerReference = "graph.ambiguous-container-reference"

    var category: InnoDIDiagnosticCategory {
        switch self {
        case .provideSingleBinding, .provideNamedPropertyRequired, .provideExplicitTypeRequired,
                .provideUnknownScope, .provideInputInvalidConfiguration, .transientFactoryUnnamedParameters:
            return .usage
        case .provideSharedFactoryRequired, .provideTransientFactoryRequired, .provideConcreteOptInRequired,
                .provideFactoryConflict, .provideAsyncFactoryInvalidScope, .provideAsyncFactoryMustBeAsync,
                .provideUnresolvedFactoryParameter, .provideUnavailableDependencyReference, .provideUnresolvedWithDependency,
                .containerUnknownDependency, .containerDependencyCycle, .containerMainActorConflict,
                .containerCustomInitUnsupported, .graphDependencyCycle,
                .graphAmbiguousContainerReference:
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
            "Dependency cycle detected in container: \(path).",
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
}
