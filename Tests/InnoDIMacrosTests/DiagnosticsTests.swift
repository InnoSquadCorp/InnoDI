import Testing
import SwiftDiagnostics

@testable import InnoDIMacros

@Suite("InnoDI Diagnostic IDs")
struct DiagnosticsTests {
    @Test("Diagnostic code categories map to expected domains")
    func diagnosticCodeCategoryDomains() {
        let usageCodes: [InnoDIDiagnosticCode] = [
            .provideSingleBinding,
            .provideNamedPropertyRequired,
            .provideExplicitTypeRequired,
            .provideUnknownScope,
            .provideInputInvalidConfiguration,
            .transientFactoryUnnamedParameters
        ]

        let validationCodes: [InnoDIDiagnosticCode] = [
            .provideSharedFactoryRequired,
            .provideTransientFactoryRequired,
            .provideConcreteOptInRequired
        ]

        for code in usageCodes {
            #expect(code.category == .usage)
        }

        for code in validationCodes {
            #expect(code.category == .validation)
        }
    }

    @Test("Diagnostic factories expose stable MessageID values")
    func diagnosticFactoriesExposeStableMessageIDValues() {
        let cases: [(diag: SimpleDiagnostic, expectedID: MessageID)] = [
            (SimpleDiagnostic.provideSingleBinding(), MessageID(domain: "InnoDI.usage", id: "provide.single-binding")),
            (SimpleDiagnostic.provideNamedPropertyRequired(), MessageID(domain: "InnoDI.usage", id: "provide.named-property-required")),
            (SimpleDiagnostic.provideExplicitTypeRequired(), MessageID(domain: "InnoDI.usage", id: "provide.explicit-type-required")),
            (SimpleDiagnostic.provideUnknownScope("foo"), MessageID(domain: "InnoDI.usage", id: "provide.unknown-scope")),
            (SimpleDiagnostic.provideInputInvalidConfiguration(), MessageID(domain: "InnoDI.usage", id: "provide.input-invalid-configuration")),
            (SimpleDiagnostic.transientFactoryUnnamedParameters(), MessageID(domain: "InnoDI.usage", id: "transient-factory.unnamed-parameters")),
            (SimpleDiagnostic.provideSharedFactoryRequired(), MessageID(domain: "InnoDI.validation", id: "provide.shared-factory-required")),
            (SimpleDiagnostic.provideTransientFactoryRequired(), MessageID(domain: "InnoDI.validation", id: "provide.transient-factory-required")),
            (SimpleDiagnostic.provideConcreteOptInRequired(name: "service", typeDescription: "Service"), MessageID(domain: "InnoDI.validation", id: "provide.concrete-opt-in-required"))
        ]

        for item in cases {
            #expect(item.diag.diagnosticID == item.expectedID)
        }
    }
}
