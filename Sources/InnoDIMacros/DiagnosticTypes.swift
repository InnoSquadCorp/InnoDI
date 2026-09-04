//
//  DiagnosticTypes.swift
//  InnoDIMacros
//
//  Stable diagnostic identities and transport types used by the InnoDI
//  macros. Message factories live in DiagnosticMessages.swift. Every code is
//  also described in the DocC `DiagnosticsGuide` article
//  (Sources/InnoDI/InnoDI.docc/DiagnosticsGuide.md) — keep the two in sync
//  when adding or renaming a case so that tools surfacing the diagnostic
//  ID can link to documentation.
//

import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

extension MacroExpansionContext {
    /// Emits `message` anchored at `node`.
    ///
    /// Every validation site otherwise repeats the same
    /// `diagnose(Diagnostic(node:message:))` wrapping; sites that need
    /// `position:` or `highlights:` keep constructing `Diagnostic` directly.
    func emit(
        _ message: some DiagnosticMessage,
        at node: some SyntaxProtocol,
        notes: [Note] = [],
        fixIts: [FixIt] = []
    ) {
        diagnose(
            Diagnostic(
                node: node,
                message: message,
                notes: notes,
                fixIts: fixIts
            )
        )
    }
}

enum InnoDIDiagnosticCategory: String {
    case usage
    case validation
}

enum InnoDIDiagnosticCode: String, CaseIterable {
    case provideSingleBinding = "provide.single-binding"
    case provideNamedPropertyRequired = "provide.named-property-required"
    case provideExplicitTypeRequired = "provide.explicit-type-required"
    case provideEscapedIdentifierUnsupported = "provide.escaped-identifier-unsupported"
    case subSingleBinding = "sub.single-binding"
    case subNamedPropertyRequired = "sub.named-property-required"
    case subExplicitTypeRequired = "sub.explicit-type-required"
    case subEscapedIdentifierUnsupported = "sub.escaped-identifier-unsupported"
    case subRequiresDirectContainerMember = "sub.requires-direct-container-member"
    case subConditionalDeclarationUnsupported = "sub.conditional-declaration-unsupported"
    case subDuplicateAttribute = "sub.duplicate-attribute"
    case subGeneratedAccessorManualAttachment = "sub.generated-accessor-manual-attachment"
    case provideUnknownScope = "provide.unknown-scope"
    case provideRequiresDirectContainerMember = "provide.requires-direct-container-member"
    case provideConditionalDeclarationUnsupported = "provide.conditional-declaration-unsupported"
    case provideDuplicateAttribute = "provide.duplicate-attribute"
    case provideGeneratedAccessorManualAttachment = "provide.generated-accessor-manual-attachment"
    case assistedFactoryInvalidDeclaration = "assisted-factory.invalid-declaration"
    case assistedFactoryMissingDeclaration = "assisted-factory.missing-declaration"
    case assistedFactoryInvalidArguments = "assisted-factory.invalid-arguments"
    case assistedFactoryDuplicateInput = "assisted-factory.duplicate-input"
    case assistedFactoryInputPartitionMismatch = "assisted-factory.input-partition-mismatch"
    case multibindingInvalidContributors = "multibinding.invalid-contributors"
    case multibindingEmptyContributors = "multibinding.empty-contributors"
    case multibindingDuplicateContributor = "multibinding.duplicate-contributor"
    case multibindingCollectionTypeRequired = "multibinding.collection-type-required"
    case multibindingUnknownContributor = "multibinding.unknown-contributor"
    case multibindingAsyncContributor = "multibinding.async-contributor"
    case multibindingTypeMismatch = "multibinding.type-mismatch"
    case provideSharedFactoryRequired = "provide.shared-factory-required"
    case provideTransientFactoryRequired = "provide.transient-factory-required"
    case provideInputInvalidConfiguration = "provide.input-invalid-configuration"
    case provideEscapingInvalidScope = "provide.escaping-invalid-scope"
    case provideEscapingNonFunctionType = "provide.escaping-nonfunction-type"
    case provideFactoryConflict = "provide.factory-conflict"
    case provideConstructionSourceConflict = "provide.construction-source-conflict"
    case provideWithRequiresTypeConstruction = "provide.with-requires-type-construction"
    case provideAsyncFactoryInvalidScope = "provide.async-factory-invalid-scope"
    case provideAsyncFactoryMustBeAsync = "provide.async-factory-must-be-async"
    case provideFactoryMustBeSync = "provide.factory-must-be-sync"
    case provideFactoryMustNotThrow = "provide.factory-must-not-throw"
    case provideBoolLiteralRequired = "provide.bool-literal-required"
    case provideInvalidWithDependencies = "provide.invalid-with-dependencies"
    case provideOpaqueTypeUnsupported = "provide.opaque-type-unsupported"
    case provideIUOTypeUnsupported = "provide.iuo-type-unsupported"
    case provideLazyUnsupportedTarget = "provide.lazy-unsupported-target"
    case provideLazyEagerCall = "provide.lazy-eager-call"
    case provideProviderNonTransientTarget = "provide.provider-non-transient-target"
    case provideProviderUnsupportedTarget = "provide.provider-unsupported-target"
    case provideProviderEagerCall = "provide.provider-eager-call"
    case provideAsyncDependencyRequiresAsyncConsumer = "provide.async-dependency-requires-async-consumer"
    case provideThrowingDependencyRequiresThrowingConsumer = "provide.throwing-dependency-requires-throwing-consumer"
    case provideWithDependencyRequiresSynchronousProvider = "provide.with-dependency-requires-synchronous-provider"
    case provideDuplicateFactoryParameter = "provide.duplicate-factory-parameter"
    case provideUnresolvedFactoryParameter = "provide.unresolved-factory-parameter"
    case provideUnavailableDependencyReference = "provide.unavailable-dependency-reference"
    case provideUnresolvedWithDependency = "provide.unresolved-with-dependency"
    case transientFactoryUnnamedParameters = "transient-factory.unnamed-parameters"
    case containerUnknownDependency = "container.unknown-dependency"
    case containerDependencyCycle = "container.dependency-cycle"
    case containerMainActorConflict = "container.mainactor-conflict"
    case containerMainActorNonisolatedMember = "container.mainactor-nonisolated-member"
    case containerRoleTokenRequired = "container.role-token-required"
    case containerBoolLiteralRequired = "container.bool-literal-required"
    case containerCustomInitUnsupported = "container.custom-init-unsupported"
    case containerUnmanagedStoredProperty = "container.unmanaged-stored-property"
    case containerOverridesNameConflict = "container.overrides-name-conflict"
    case containerReservedNamePrefix = "container.reserved-name-prefix"
    case containerReservedModuleName = "container.reserved-module-name"
    case containerDuplicateMemberName = "container.duplicate-member-name"
    case containerGeneratedSymbolCollision = "container.generated-symbol-collision"
    case containerUnsupportedDeclarationKind = "container.unsupported-declaration-kind"
    case containerPrivateAccessUnsupported = "container.private-access-unsupported"
    case containerGenericUnsupported = "container.generic-unsupported"
    case containerUnverifiableEnclosingContext = "container.unverifiable-enclosing-context"
    case containerLocalDeclarationUnsupported = "container.local-declaration-unsupported"
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
    case swiftUIFeatureRootDuplicateDefault = "swiftui.feature-root-duplicate-default"
    case swiftUIFeatureRootHelperNameConflict = "swiftui.feature-root-helper-name-conflict"
    case swiftUIFeatureRootInvalidAlias = "swiftui.feature-root-invalid-alias"
    case swiftUIFeatureRootInvalidRoot = "swiftui.feature-root-invalid-root"
    case swiftUIEnvironmentBridgeUnknownMember = "swiftui.environment-bridge-unknown-member"
    case swiftUIEnvironmentBridgeDuplicateMember = "swiftui.environment-bridge-duplicate-member"
    case swiftUIEnvironmentBridgeAsyncMember = "swiftui.environment-bridge-async-member"
    case swiftUIEnvironmentBridgeInvalidKeyPath = "swiftui.environment-bridge-invalid-keypath"
    case swiftUIEnvironmentBridgeInvalidArguments = "swiftui.environment-bridge-invalid-arguments"
    case swiftUIEnvironmentBridgeReservedModuleName = "swiftui.environment-bridge-reserved-module-name"
    case swiftUIEnvironmentBridgeGeneratedNameConflict = "swiftui.environment-bridge-generated-name-conflict"
    case swiftUIEnvironmentBridgeExtensionContextUnsupported = "swiftui.environment-bridge-extension-context-unsupported"
    case swiftUIEnvironmentBridgeUnsupportedDeclarationKind = "swiftui.environment-bridge-unsupported-declaration-kind"
    case swiftUIEnvironmentBridgePrivateNestedTarget = "swiftui.environment-bridge-private-nested-target"
    case swiftUIEnvironmentBridgeParameterPackUnsupported = "swiftui.environment-bridge-parameter-pack-unsupported"
    case componentRequiresContainer = "component.requires-container"
    case componentEscapedTargetUnsupported = "component.escaped-target-unsupported"
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
                .provideEscapedIdentifierUnsupported,
                .subSingleBinding, .subNamedPropertyRequired, .subExplicitTypeRequired,
                .subEscapedIdentifierUnsupported,
                .subRequiresDirectContainerMember,
                .subConditionalDeclarationUnsupported,
                .subDuplicateAttribute,
                .subGeneratedAccessorManualAttachment,
                .provideUnknownScope, .provideRequiresDirectContainerMember,
                .provideConditionalDeclarationUnsupported,
                .provideDuplicateAttribute,
                .provideGeneratedAccessorManualAttachment,
                .assistedFactoryInvalidDeclaration,
                .assistedFactoryInvalidArguments,
                .multibindingInvalidContributors,
                .provideInputInvalidConfiguration, .transientFactoryUnnamedParameters,
                .containerUnsupportedDeclarationKind, .containerPrivateAccessUnsupported,
                .containerGenericUnsupported,
                .containerUnverifiableEnclosingContext, .containerLocalDeclarationUnsupported,
                .containerUnmanagedStoredProperty,
                .swiftUIEnvironmentBridgeExtensionContextUnsupported,
                .swiftUIEnvironmentBridgeUnsupportedDeclarationKind,
                .swiftUIEnvironmentBridgePrivateNestedTarget,
                .swiftUIEnvironmentBridgeParameterPackUnsupported,
                .componentEscapedTargetUnsupported:
            return .usage
        case .provideSharedFactoryRequired, .provideTransientFactoryRequired,
                .provideFactoryConflict, .provideConstructionSourceConflict,
                .provideWithRequiresTypeConstruction,
                .assistedFactoryMissingDeclaration,
                .assistedFactoryDuplicateInput,
                .assistedFactoryInputPartitionMismatch,
                .multibindingEmptyContributors,
                .multibindingDuplicateContributor,
                .multibindingCollectionTypeRequired,
                .multibindingUnknownContributor,
                .multibindingAsyncContributor,
                .multibindingTypeMismatch,
                .provideAsyncFactoryInvalidScope, .provideAsyncFactoryMustBeAsync,
                .provideFactoryMustBeSync, .provideFactoryMustNotThrow,
                .provideEscapingInvalidScope,
                .provideEscapingNonFunctionType,
                .provideBoolLiteralRequired, .provideInvalidWithDependencies,
                .provideOpaqueTypeUnsupported,
                .provideIUOTypeUnsupported,
                .provideLazyUnsupportedTarget, .provideLazyEagerCall,
                .provideProviderNonTransientTarget, .provideProviderUnsupportedTarget, .provideProviderEagerCall,
                .provideAsyncDependencyRequiresAsyncConsumer,
                .provideThrowingDependencyRequiresThrowingConsumer,
                .provideWithDependencyRequiresSynchronousProvider,
                .provideDuplicateFactoryParameter,
                .provideUnresolvedFactoryParameter, .provideUnavailableDependencyReference, .provideUnresolvedWithDependency,
                .containerUnknownDependency, .containerDependencyCycle, .containerMainActorConflict,
                .containerMainActorNonisolatedMember,
                .containerRoleTokenRequired,
                .containerBoolLiteralRequired,
                .containerCustomInitUnsupported, .containerOverridesNameConflict,
                .containerReservedNamePrefix, .containerReservedModuleName,
                .containerDuplicateMemberName,
                .containerGeneratedSymbolCollision,
                .graphDependencyCycle,
                .graphAmbiguousContainerReference,
                .subScopeRequired, .subUnknownScope, .subConflictsWithProvide, .subOverridesNameConflict,
                .subUnknownParentMember, .subBindingsConflictsWithWith,
                .subInvalidSameNameWiring, .subInvalidBindings,
                .subDuplicateChildBinding, .subUnknownChildInput, .subAutoWiringAmbiguous,
                .subSharedParentMustNotBeTransient,
                .provideLazyAliased, .provideProviderAliased,
                .swiftUIFeatureRootDuplicateDefault, .swiftUIFeatureRootInvalidAlias,
                .swiftUIFeatureRootInvalidRoot,
                .swiftUIFeatureRootHelperNameConflict, .swiftUIEnvironmentBridgeUnknownMember,
                .swiftUIEnvironmentBridgeDuplicateMember, .swiftUIEnvironmentBridgeAsyncMember,
                .swiftUIEnvironmentBridgeInvalidKeyPath,
                .swiftUIEnvironmentBridgeInvalidArguments,
                .swiftUIEnvironmentBridgeReservedModuleName,
                .swiftUIEnvironmentBridgeGeneratedNameConflict,
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
    let message: String
    let fixItID: MessageID

    init(_ message: String, code: InnoDIDiagnosticCode, suffix: String) {
        self.message = message
        self.fixItID = MessageID(domain: "InnoDI.\(code.category.rawValue)", id: "\(code.rawValue).fixit.\(suffix)")
    }
}

/// Replaces exactly the trivia-stripped text of `syntax` with `replacement`.
/// Shared by the mechanical fix-its (`some` → `any`, `T!` → `T?`,
/// `private` → `fileprivate`) so they all edit source the same way.
internal func makeTextReplacementFixIt(
    replacing syntax: some SyntaxProtocol,
    with replacement: String,
    message: String,
    code: InnoDIDiagnosticCode,
    suffix: String = "replace"
) -> FixIt {
    FixIt(
        message: SimpleFixIt(message, code: code, suffix: suffix),
        changes: [
            .replaceText(
                range: syntax.positionAfterSkippingLeadingTrivia..<syntax.endPositionBeforeTrailingTrivia,
                with: replacement,
                in: Syntax(syntax.root)
            )
        ]
    )
}

/// Removes `syntax` and the whitespace before the next token while leaving
/// the removed syntax's leading trivia (including comments and indentation)
/// in place. The next token therefore occupies the attribute's former column
/// instead of being separated by an empty line.
internal func makeRemovalFixIt(
    removing syntax: some SyntaxProtocol,
    message: String,
    code: InnoDIDiagnosticCode
) -> FixIt {
    let removalEnd = syntax.lastToken(viewMode: .sourceAccurate)?
        .nextToken(viewMode: .sourceAccurate)?
        .positionAfterSkippingLeadingTrivia
        ?? syntax.endPosition
    return FixIt(
        message: SimpleFixIt(message, code: code, suffix: "remove"),
        changes: [
            .replaceText(
                range: syntax.positionAfterSkippingLeadingTrivia..<removalEnd,
                with: "",
                in: Syntax(syntax.root)
            )
        ]
    )
}
