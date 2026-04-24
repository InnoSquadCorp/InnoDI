import Foundation
import Testing
import SwiftDiagnostics

@testable import InnoDIMacros

@Suite("InnoDI Diagnostic IDs")
struct DiagnosticsTests {
    @Test("Diagnostics guide lists every diagnostic code")
    func diagnosticsGuideListsEveryDiagnosticCode() throws {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = testDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let guideURL = repositoryRoot.appendingPathComponent("Sources/InnoDI/InnoDI.docc/DiagnosticsGuide.md")
        let guide = try String(contentsOf: guideURL, encoding: .utf8)

        let missing = InnoDIDiagnosticCode.allCases
            .map(\.rawValue)
            .filter { !guide.contains("`\($0)`") }

        #expect(missing.isEmpty, "Missing diagnostic codes in DiagnosticsGuide.md: \(missing.joined(separator: ", "))")
    }

    @Test("Diagnostic code categories map to expected domains")
    func diagnosticCodeCategoryDomains() {
        let usageCodes: [InnoDIDiagnosticCode] = [
            .provideSingleBinding,
            .provideNamedPropertyRequired,
            .provideExplicitTypeRequired,
            .subSingleBinding,
            .subNamedPropertyRequired,
            .subExplicitTypeRequired,
            .provideUnknownScope,
            .provideInputInvalidConfiguration,
            .transientFactoryUnnamedParameters
        ]

        let validationCodes: [InnoDIDiagnosticCode] = [
            .provideSharedFactoryRequired,
            .provideTransientFactoryRequired,
            .provideConcreteOptInRequired,
            .provideFactoryConflict,
            .provideAsyncFactoryInvalidScope,
            .provideAsyncFactoryMustBeAsync,
            .provideLazyUnsupportedTarget,
            .provideProviderNonTransientTarget,
            .provideProviderUnsupportedTarget,
            .provideProviderEagerCall,
            .provideUnresolvedFactoryParameter,
            .provideUnavailableDependencyReference,
            .provideUnresolvedWithDependency,
            .containerUnknownDependency,
            .containerDependencyCycle,
            .containerMainActorConflict,
            .containerCustomInitUnsupported,
            .containerOverridesNameConflict,
            .graphDependencyCycle,
            .graphAmbiguousContainerReference,
            .subScopeRequired,
            .subUnknownScope,
            .subConflictsWithProvide,
            .subOverridesNameConflict,
            .subUnknownParentMember,
            .subBindingsConflictsWithWith,
            .subDuplicateChildBinding,
            .subUnknownChildInput,
            .subAutoWiringAmbiguous,
            .subSharedParentMustNotBeTransient
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
            (SimpleDiagnostic.subSingleBinding(), MessageID(domain: "InnoDI.usage", id: "sub.single-binding")),
            (SimpleDiagnostic.subNamedPropertyRequired(), MessageID(domain: "InnoDI.usage", id: "sub.named-property-required")),
            (SimpleDiagnostic.subExplicitTypeRequired(), MessageID(domain: "InnoDI.usage", id: "sub.explicit-type-required")),
            (SimpleDiagnostic.provideUnknownScope("foo"), MessageID(domain: "InnoDI.usage", id: "provide.unknown-scope")),
            (SimpleDiagnostic.provideInputInvalidConfiguration(), MessageID(domain: "InnoDI.usage", id: "provide.input-invalid-configuration")),
            (SimpleDiagnostic.transientFactoryUnnamedParameters(), MessageID(domain: "InnoDI.usage", id: "transient-factory.unnamed-parameters")),
            (SimpleDiagnostic.provideSharedFactoryRequired(), MessageID(domain: "InnoDI.validation", id: "provide.shared-factory-required")),
            (SimpleDiagnostic.provideTransientFactoryRequired(), MessageID(domain: "InnoDI.validation", id: "provide.transient-factory-required")),
            (SimpleDiagnostic.provideConcreteOptInRequired(name: "service", typeDescription: "Service"), MessageID(domain: "InnoDI.validation", id: "provide.concrete-opt-in-required")),
            (SimpleDiagnostic.provideFactoryConflict(), MessageID(domain: "InnoDI.validation", id: "provide.factory-conflict")),
            (SimpleDiagnostic.provideAsyncFactoryInvalidScope(), MessageID(domain: "InnoDI.validation", id: "provide.async-factory-invalid-scope")),
            (SimpleDiagnostic.provideAsyncFactoryMustBeAsync(), MessageID(domain: "InnoDI.validation", id: "provide.async-factory-must-be-async")),
            (SimpleDiagnostic.provideLazyUnsupportedTarget(memberName: "serviceA", dependencyName: "serviceB"), MessageID(domain: "InnoDI.validation", id: "provide.lazy-unsupported-target")),
            (SimpleDiagnostic.provideProviderNonTransientTarget(memberName: "consumer", dependencyName: "service", targetScope: .shared), MessageID(domain: "InnoDI.validation", id: "provide.provider-non-transient-target")),
            (SimpleDiagnostic.provideProviderUnsupportedTarget(memberName: "consumer", dependencyName: "service"), MessageID(domain: "InnoDI.validation", id: "provide.provider-unsupported-target")),
            (SimpleDiagnostic.provideProviderEagerCall(memberName: "consumer", dependencyName: "service"), MessageID(domain: "InnoDI.validation", id: "provide.provider-eager-call")),
            (SimpleDiagnostic.provideUnresolvedFactoryParameter(memberName: "service", parameterName: "missing"), MessageID(domain: "InnoDI.validation", id: "provide.unresolved-factory-parameter")),
            (SimpleDiagnostic.provideUnavailableDependencyReference(memberName: "service", dependencyName: "later"), MessageID(domain: "InnoDI.validation", id: "provide.unavailable-dependency-reference")),
            (SimpleDiagnostic.provideUnresolvedWithDependency(memberName: "service", dependencyName: "missing"), MessageID(domain: "InnoDI.validation", id: "provide.unresolved-with-dependency")),
            (SimpleDiagnostic.containerUnknownDependency(dependencyName: "missing", memberName: "service"), MessageID(domain: "InnoDI.validation", id: "container.unknown-dependency")),
            (SimpleDiagnostic.containerDependencyCycle(path: "a -> b -> a"), MessageID(domain: "InnoDI.validation", id: "container.dependency-cycle")),
            (SimpleDiagnostic.containerMainActorConflict(actorName: "FeatureActor"), MessageID(domain: "InnoDI.validation", id: "container.mainactor-conflict")),
            (SimpleDiagnostic.containerCustomInitUnsupported(), MessageID(domain: "InnoDI.validation", id: "container.custom-init-unsupported")),
            (SimpleDiagnostic.containerOverridesNameConflict(kind: "struct"), MessageID(domain: "InnoDI.validation", id: "container.overrides-name-conflict")),
            (SimpleDiagnostic("Graph cycle", code: .graphDependencyCycle), MessageID(domain: "InnoDI.validation", id: "graph.dependency-cycle")),
            (SimpleDiagnostic("Ambiguous reference", code: .graphAmbiguousContainerReference), MessageID(domain: "InnoDI.validation", id: "graph.ambiguous-container-reference")),
            (SimpleDiagnostic.subScopeRequired(memberName: "feature"), MessageID(domain: "InnoDI.validation", id: "sub.scope-required")),
            (SimpleDiagnostic.subUnknownScope(memberName: "feature", scopeName: "request"), MessageID(domain: "InnoDI.validation", id: "sub.unknown-scope")),
            (SimpleDiagnostic.subConflictsWithProvide(memberName: "feature"), MessageID(domain: "InnoDI.validation", id: "sub.conflicts-with-provide")),
            (SimpleDiagnostic.subOverridesNameConflict(memberName: "feature", generatedName: "featureOverrides"), MessageID(domain: "InnoDI.validation", id: "sub.overrides-name-conflict")),
            (SimpleDiagnostic.subUnknownParentMember(memberName: "feature", parentMemberName: "missing"), MessageID(domain: "InnoDI.validation", id: "sub.unknown-parent-member")),
            (SimpleDiagnostic.subAutoWiringAmbiguous(memberName: "feature"), MessageID(domain: "InnoDI.validation", id: "sub.auto-wiring-ambiguous")),
            (SimpleDiagnostic.subSharedParentMustNotBeTransient(memberName: "feature", parentMemberName: "request"), MessageID(domain: "InnoDI.validation", id: "sub.shared-parent-must-not-be-transient"))
        ]

        for item in cases {
            #expect(item.diag.diagnosticID == item.expectedID)
        }
    }
}
