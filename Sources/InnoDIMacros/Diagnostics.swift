//
//  Diagnostics.swift
//  InnoDIMacros
//

import SwiftDiagnostics

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
    case transientFactoryUnnamedParameters = "transient-factory.unnamed-parameters"

    var category: InnoDIDiagnosticCategory {
        switch self {
        case .provideSingleBinding, .provideNamedPropertyRequired, .provideExplicitTypeRequired,
                .provideUnknownScope, .provideInputInvalidConfiguration, .transientFactoryUnnamedParameters:
            return .usage
        case .provideSharedFactoryRequired, .provideTransientFactoryRequired, .provideConcreteOptInRequired:
            return .validation
        }
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
        self.diagnosticID = MessageID(domain: "InnoDI.\(code.category.rawValue)", id: code.rawValue)
        self.severity = severity
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

    static func transientFactoryUnnamedParameters() -> Self {
        Self(
            "Transient factory closure parameters must be named for injection.",
            code: .transientFactoryUnnamedParameters
        )
    }
}
