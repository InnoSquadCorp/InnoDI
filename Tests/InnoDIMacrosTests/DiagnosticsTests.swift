import Foundation
import Testing
import SwiftDiagnostics
import InnoDICore

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
            .provideEscapedIdentifierUnsupported,
            .subSingleBinding,
            .subNamedPropertyRequired,
            .subExplicitTypeRequired,
            .subEscapedIdentifierUnsupported,
            .subRequiresDirectContainerMember,
            .subConditionalDeclarationUnsupported,
            .subDuplicateAttribute,
            .subGeneratedAccessorManualAttachment,
            .provideUnknownScope,
            .provideRequiresDirectContainerMember,
            .provideConditionalDeclarationUnsupported,
            .provideDuplicateAttribute,
            .provideGeneratedAccessorManualAttachment,
            .provideInputInvalidConfiguration,
            .transientFactoryUnnamedParameters,
            .containerUnsupportedDeclarationKind,
            .containerPrivateAccessUnsupported,
            .containerGenericUnsupported,
            .containerUnverifiableEnclosingContext,
            .containerLocalDeclarationUnsupported,
            .containerUnmanagedStoredProperty,
            .swiftUIEnvironmentBridgeExtensionContextUnsupported,
            .swiftUIEnvironmentBridgeUnsupportedDeclarationKind,
            .swiftUIEnvironmentBridgePrivateNestedTarget,
            .componentEscapedTargetUnsupported
        ]

        let validationCodes: [InnoDIDiagnosticCode] = [
            .provideSharedFactoryRequired,
            .provideTransientFactoryRequired,
            .provideFactoryConflict,
            .provideConstructionSourceConflict,
            .provideWithRequiresTypeConstruction,
            .provideAsyncFactoryInvalidScope,
            .provideAsyncFactoryMustBeAsync,
            .provideFactoryMustBeSync,
            .provideFactoryMustNotThrow,
            .provideEscapingInvalidScope,
            .provideEscapingNonFunctionType,
            .provideBoolLiteralRequired,
            .provideInvalidWithDependencies,
            .provideOpaqueTypeUnsupported,
            .provideIUOTypeUnsupported,
            .provideLazyUnsupportedTarget,
            .provideProviderNonTransientTarget,
            .provideProviderUnsupportedTarget,
            .provideProviderEagerCall,
            .provideAsyncDependencyRequiresAsyncConsumer,
            .provideThrowingDependencyRequiresThrowingConsumer,
            .provideWithDependencyRequiresSynchronousProvider,
            .provideDuplicateFactoryParameter,
            .provideUnresolvedFactoryParameter,
            .provideUnavailableDependencyReference,
            .provideUnresolvedWithDependency,
            .containerUnknownDependency,
            .containerDependencyCycle,
            .containerMainActorConflict,
            .containerMainActorNonisolatedMember,
            .containerBoolLiteralRequired,
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
            .subInvalidSameNameWiring,
            .subInvalidBindings,
            .subDuplicateChildBinding,
            .subUnknownChildInput,
            .subAutoWiringAmbiguous,
            .subSharedParentMustNotBeTransient,
            .swiftUIEnvironmentBridgeAsyncMember,
            .swiftUIEnvironmentBridgeReservedModuleName,
            .swiftUIEnvironmentBridgeGeneratedNameConflict,
            .containerReservedNamePrefix,
            .containerReservedModuleName,
            .containerDuplicateMemberName,
            .containerGeneratedSymbolCollision
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
            (SimpleDiagnostic.provideEscapedPropertyIdentifier(memberName: "default"), MessageID(domain: "InnoDI.usage", id: "provide.escaped-identifier-unsupported")),
            (SimpleDiagnostic.provideEscapedFactoryParameter(memberName: "service", parameterName: "default"), MessageID(domain: "InnoDI.usage", id: "provide.escaped-identifier-unsupported")),
            (SimpleDiagnostic.subSingleBinding(), MessageID(domain: "InnoDI.usage", id: "sub.single-binding")),
            (SimpleDiagnostic.subNamedPropertyRequired(), MessageID(domain: "InnoDI.usage", id: "sub.named-property-required")),
            (SimpleDiagnostic.subExplicitTypeRequired(), MessageID(domain: "InnoDI.usage", id: "sub.explicit-type-required")),
            (SimpleDiagnostic.subEscapedPropertyIdentifier(memberName: "default"), MessageID(domain: "InnoDI.usage", id: "sub.escaped-identifier-unsupported")),
            (SimpleDiagnostic.subRequiresDirectContainerMember(memberName: "feature"), MessageID(domain: "InnoDI.usage", id: "sub.requires-direct-container-member")),
            (SimpleDiagnostic.subConditionalDeclarationUnsupported(memberName: "feature"), MessageID(domain: "InnoDI.usage", id: "sub.conditional-declaration-unsupported")),
            (SimpleDiagnostic.subDuplicateAttribute(memberName: "feature"), MessageID(domain: "InnoDI.usage", id: "sub.duplicate-attribute")),
            (SimpleDiagnostic.subGeneratedAccessorManualAttachment(memberName: "feature"), MessageID(domain: "InnoDI.usage", id: "sub.generated-accessor-manual-attachment")),
            (SimpleDiagnostic.provideUnknownScope("foo"), MessageID(domain: "InnoDI.usage", id: "provide.unknown-scope")),
            (SimpleDiagnostic.provideRequiresDirectContainerMember(memberName: "service"), MessageID(domain: "InnoDI.usage", id: "provide.requires-direct-container-member")),
            (SimpleDiagnostic.provideConditionalDeclarationUnsupported(memberName: "service"), MessageID(domain: "InnoDI.usage", id: "provide.conditional-declaration-unsupported")),
            (SimpleDiagnostic.provideDuplicateAttribute(memberName: "service"), MessageID(domain: "InnoDI.usage", id: "provide.duplicate-attribute")),
            (SimpleDiagnostic.provideGeneratedAccessorManualAttachment(memberName: "service"), MessageID(domain: "InnoDI.usage", id: "provide.generated-accessor-manual-attachment")),
            (SimpleDiagnostic.provideInputInvalidConfiguration(), MessageID(domain: "InnoDI.usage", id: "provide.input-invalid-configuration")),
            (SimpleDiagnostic.transientFactoryUnnamedParameters(), MessageID(domain: "InnoDI.usage", id: "transient-factory.unnamed-parameters")),
            (SimpleDiagnostic.containerUnsupportedDeclarationKind(name: "AppContainer", kind: "class"), MessageID(domain: "InnoDI.usage", id: "container.unsupported-declaration-kind")),
            (SimpleDiagnostic.containerPrivateAccessUnsupported(name: "AppContainer"), MessageID(domain: "InnoDI.usage", id: "container.private-access-unsupported")),
            (SimpleDiagnostic.containerGenericUnsupported(name: "AppContainer", contextName: nil), MessageID(domain: "InnoDI.usage", id: "container.generic-unsupported")),
            (SimpleDiagnostic.containerUnverifiableEnclosingContext(name: "AppContainer", extendedType: "Feature"), MessageID(domain: "InnoDI.usage", id: "container.unverifiable-enclosing-context")),
            (SimpleDiagnostic.containerLocalDeclarationUnsupported(name: "AppContainer", context: "function 'build'"), MessageID(domain: "InnoDI.usage", id: "container.local-declaration-unsupported")),
            (SimpleDiagnostic.containerUnmanagedStoredProperty(memberName: "token"), MessageID(domain: "InnoDI.usage", id: "container.unmanaged-stored-property")),
            (SimpleDiagnostic.provideSharedFactoryRequired(), MessageID(domain: "InnoDI.validation", id: "provide.shared-factory-required")),
            (SimpleDiagnostic.provideTransientFactoryRequired(), MessageID(domain: "InnoDI.validation", id: "provide.transient-factory-required")),
            (SimpleDiagnostic.provideFactoryConflict(), MessageID(domain: "InnoDI.validation", id: "provide.factory-conflict")),
            (SimpleDiagnostic.provideConstructionSourceConflict(memberName: "service"), MessageID(domain: "InnoDI.validation", id: "provide.construction-source-conflict")),
            (SimpleDiagnostic.provideWithRequiresTypeConstruction(memberName: "service"), MessageID(domain: "InnoDI.validation", id: "provide.with-requires-type-construction")),
            (SimpleDiagnostic.provideAsyncFactoryInvalidScope(), MessageID(domain: "InnoDI.validation", id: "provide.async-factory-invalid-scope")),
            (SimpleDiagnostic.provideAsyncFactoryMustBeAsync(), MessageID(domain: "InnoDI.validation", id: "provide.async-factory-must-be-async")),
            (SimpleDiagnostic.provideFactoryMustBeSync(memberName: "service"), MessageID(domain: "InnoDI.validation", id: "provide.factory-must-be-sync")),
            (SimpleDiagnostic.provideFactoryMustNotThrow(memberName: "service"), MessageID(domain: "InnoDI.validation", id: "provide.factory-must-not-throw")),
            (SimpleDiagnostic.provideEscapingInvalidScope(memberName: "service"), MessageID(domain: "InnoDI.validation", id: "provide.escaping-invalid-scope")),
            (SimpleDiagnostic.provideEscapingNonFunctionType(memberName: "handler"), MessageID(domain: "InnoDI.validation", id: "provide.escaping-nonfunction-type")),
            (SimpleDiagnostic.provideBoolLiteralRequired(label: "escaping"), MessageID(domain: "InnoDI.validation", id: "provide.bool-literal-required")),
            (SimpleDiagnostic.provideInvalidWithDependencies(memberName: "service", expectedRoot: "Self"), MessageID(domain: "InnoDI.validation", id: "provide.invalid-with-dependencies")),
            (SimpleDiagnostic.provideOpaqueTypeUnsupported(memberName: "service"), MessageID(domain: "InnoDI.validation", id: "provide.opaque-type-unsupported")),
            (SimpleDiagnostic.provideIUOTypeUnsupported(memberName: "service"), MessageID(domain: "InnoDI.validation", id: "provide.iuo-type-unsupported")),
            (SimpleDiagnostic.provideLazyUnsupportedTarget(memberName: "serviceA", dependencyName: "serviceB"), MessageID(domain: "InnoDI.validation", id: "provide.lazy-unsupported-target")),
            (SimpleDiagnostic.provideProviderNonTransientTarget(memberName: "consumer", dependencyName: "service", targetScope: .shared), MessageID(domain: "InnoDI.validation", id: "provide.provider-non-transient-target")),
            (SimpleDiagnostic.provideProviderUnsupportedTarget(memberName: "consumer", dependencyName: "service"), MessageID(domain: "InnoDI.validation", id: "provide.provider-unsupported-target")),
            (SimpleDiagnostic.provideProviderEagerCall(memberName: "consumer", dependencyName: "service"), MessageID(domain: "InnoDI.validation", id: "provide.provider-eager-call")),
            (SimpleDiagnostic.provideAsyncDependencyRequiresAsyncConsumer(memberName: "session", dependencyName: "token", providerThrows: false), MessageID(domain: "InnoDI.validation", id: "provide.async-dependency-requires-async-consumer")),
            (SimpleDiagnostic.provideThrowingDependencyRequiresThrowingConsumer(memberName: "session", dependencyName: "token"), MessageID(domain: "InnoDI.validation", id: "provide.throwing-dependency-requires-throwing-consumer")),
            (SimpleDiagnostic.provideWithDependencyRequiresSynchronousProvider(memberName: "session", dependencyName: "token", providerThrows: false), MessageID(domain: "InnoDI.validation", id: "provide.with-dependency-requires-synchronous-provider")),
            (SimpleDiagnostic.provideDuplicateFactoryParameter(memberName: "session", parameterName: "token"), MessageID(domain: "InnoDI.validation", id: "provide.duplicate-factory-parameter")),
            (SimpleDiagnostic.provideUnresolvedFactoryParameter(memberName: "service", parameterName: "missing"), MessageID(domain: "InnoDI.validation", id: "provide.unresolved-factory-parameter")),
            (SimpleDiagnostic.provideUnavailableDependencyReference(memberName: "service", dependencyName: "later"), MessageID(domain: "InnoDI.validation", id: "provide.unavailable-dependency-reference")),
            (SimpleDiagnostic.provideUnresolvedWithDependency(memberName: "service", dependencyName: "missing"), MessageID(domain: "InnoDI.validation", id: "provide.unresolved-with-dependency")),
            (SimpleDiagnostic.containerUnknownDependency(dependencyName: "missing", memberName: "service"), MessageID(domain: "InnoDI.validation", id: "container.unknown-dependency")),
            (SimpleDiagnostic.containerDependencyCycle(path: "a -> b -> a"), MessageID(domain: "InnoDI.validation", id: "container.dependency-cycle")),
            (SimpleDiagnostic.containerMainActorConflict(actorName: "FeatureActor"), MessageID(domain: "InnoDI.validation", id: "container.mainactor-conflict")),
            (SimpleDiagnostic.containerMainActorNonisolatedMember(memberName: "service"), MessageID(domain: "InnoDI.validation", id: "container.mainactor-nonisolated-member")),
            (SimpleDiagnostic.containerBoolLiteralRequired(label: "validateDAG"), MessageID(domain: "InnoDI.validation", id: "container.bool-literal-required")),
            (SimpleDiagnostic.containerCustomInitUnsupported(), MessageID(domain: "InnoDI.validation", id: "container.custom-init-unsupported")),
            (SimpleDiagnostic.containerOverridesNameConflict(kind: "struct"), MessageID(domain: "InnoDI.validation", id: "container.overrides-name-conflict")),
            (SimpleDiagnostic("Graph cycle", code: .graphDependencyCycle), MessageID(domain: "InnoDI.validation", id: "graph.dependency-cycle")),
            (SimpleDiagnostic("Ambiguous reference", code: .graphAmbiguousContainerReference), MessageID(domain: "InnoDI.validation", id: "graph.ambiguous-container-reference")),
            (SimpleDiagnostic.subScopeRequired(memberName: "feature"), MessageID(domain: "InnoDI.validation", id: "sub.scope-required")),
            (SimpleDiagnostic.subUnknownScope(memberName: "feature", scopeName: "request"), MessageID(domain: "InnoDI.validation", id: "sub.unknown-scope")),
            (SimpleDiagnostic.subConflictsWithProvide(memberName: "feature"), MessageID(domain: "InnoDI.validation", id: "sub.conflicts-with-provide")),
            (SimpleDiagnostic.subOverridesNameConflict(memberName: "feature", generatedName: "featureOverrides"), MessageID(domain: "InnoDI.validation", id: "sub.overrides-name-conflict")),
            (SimpleDiagnostic.subUnknownParentMember(memberName: "feature", parentMemberName: "missing"), MessageID(domain: "InnoDI.validation", id: "sub.unknown-parent-member")),
            (SimpleDiagnostic.subBindingsConflictsWithWith(memberName: "feature"), MessageID(domain: "InnoDI.validation", id: "sub.bindings-conflicts-with-with")),
            (SimpleDiagnostic.subInvalidSameNameWiring(memberName: "feature", label: .with), MessageID(domain: "InnoDI.validation", id: "sub.invalid-same-name-wiring")),
            (SimpleDiagnostic.subInvalidBindings(memberName: "feature"), MessageID(domain: "InnoDI.validation", id: "sub.invalid-bindings")),
            (SimpleDiagnostic.subAutoWiringAmbiguous(memberName: "feature"), MessageID(domain: "InnoDI.validation", id: "sub.auto-wiring-ambiguous")),
            (SimpleDiagnostic.subSharedParentMustNotBeTransient(memberName: "feature", parentMemberName: "request"), MessageID(domain: "InnoDI.validation", id: "sub.shared-parent-must-not-be-transient")),
            (SimpleDiagnostic.swiftUIEnvironmentBridgeAsyncMember(memberName: "service"), MessageID(domain: "InnoDI.validation", id: "swiftui.environment-bridge-async-member")),
            (SimpleDiagnostic.swiftUIEnvironmentBridgeInvalidEnvironmentKeyPath(), MessageID(domain: "InnoDI.validation", id: "swiftui.environment-bridge-invalid-keypath")),
            (SimpleDiagnostic.swiftUIEnvironmentBridgeReservedModuleName(declarationName: "SwiftUI"), MessageID(domain: "InnoDI.validation", id: "swiftui.environment-bridge-reserved-module-name")),
            (SimpleDiagnostic.swiftUIEnvironmentBridgeGeneratedModifierTypeNameConflict(memberName: "_InnoDIEnvironmentBridgeModifier"), MessageID(domain: "InnoDI.validation", id: "swiftui.environment-bridge-generated-name-conflict")),
            (SimpleDiagnostic.swiftUIEnvironmentBridgeGeneratedHelperNameConflict(memberName: "_innoDIEnvironmentBridgeModifier"), MessageID(domain: "InnoDI.validation", id: "swiftui.environment-bridge-generated-name-conflict")),
            (SimpleDiagnostic.swiftUIEnvironmentBridgeExtensionContextUnsupported(), MessageID(domain: "InnoDI.usage", id: "swiftui.environment-bridge-extension-context-unsupported")),
            (SimpleDiagnostic.swiftUIEnvironmentBridgeUnsupportedDeclarationKind(name: "Bridge", kind: "an actor"), MessageID(domain: "InnoDI.usage", id: "swiftui.environment-bridge-unsupported-declaration-kind")),
            (SimpleDiagnostic.swiftUIEnvironmentBridgePrivateNestedTarget(name: "Bridge"), MessageID(domain: "InnoDI.usage", id: "swiftui.environment-bridge-private-nested-target")),
            (SimpleDiagnostic.swiftUIEnvironmentBridgeParameterPackUnsupported(), MessageID(domain: "InnoDI.usage", id: "swiftui.environment-bridge-parameter-pack-unsupported")),
            (SimpleDiagnostic.componentEscapedTargetUnsupported(name: "default"), MessageID(domain: "InnoDI.usage", id: "component.escaped-target-unsupported")),
            (SimpleDiagnostic.containerReservedNamePrefix(memberName: "_storage_config", reservedPrefix: "_storage_"), MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix")),
            (SimpleDiagnostic.containerReservedModuleName(memberName: "InnoDI"), MessageID(domain: "InnoDI.validation", id: "container.reserved-module-name")),
            (SimpleDiagnostic.containerDuplicateMemberName(memberName: "service"), MessageID(domain: "InnoDI.validation", id: "container.duplicate-member-name")),
            (SimpleDiagnostic.containerGeneratedSymbolCollision(conflictingMemberName: "task_service", generatedName: "_storage_task_service", firstMemberName: "service"), MessageID(domain: "InnoDI.validation", id: "container.generated-symbol-collision"))
        ]

        for item in cases {
            #expect(item.diag.diagnosticID == item.expectedID)
        }
    }
}
