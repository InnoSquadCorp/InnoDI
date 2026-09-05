//
//  DiagnosticMessages.swift
//  InnoDIMacros
//
//  Message factories grouped separately from the stable diagnostic identity
//  registry in DiagnosticTypes.swift.
//

import InnoDICore
import SwiftDiagnostics

extension SimpleDiagnostic {
    static func provideUnknownInitialization(_ name: String) -> Self {
        Self(
            "Unknown @Provide initialization policy '\(name)'. Valid policies are .eager and .onDemand.",
            code: .provideUnknownInitialization
        )
    }

    static func provideInitializationInvalidScope(memberName: String) -> Self {
        Self(
            "@Provide member '\(memberName)' can use initialization: .onDemand only with .shared scope.",
            code: .provideInitializationInvalidScope
        )
    }

    static func provideOnDemandAsyncUnsupported(memberName: String) -> Self {
        Self(
            "@Provide member '\(memberName)' cannot combine initialization: .onDemand with asyncFactory yet; use the async scope API or eager initialization.",
            code: .provideOnDemandAsyncUnsupported
        )
    }

    static func assistedFactoryInvalidDeclaration() -> Self {
        Self(
            "@AssistedFactory must annotate an empty, non-generic nested struct named 'AssistedFactory'.",
            code: .assistedFactoryInvalidDeclaration
        )
    }

    static func assistedFactoryMissingDeclaration() -> Self {
        Self(
            "A container with @Input(.assisted) must declare an empty nested '@AssistedFactory struct AssistedFactory {}'.",
            code: .assistedFactoryMissingDeclaration
        )
    }

    static func assistedFactoryInvalidArguments() -> Self {
        Self(
            "@AssistedFactory requires Child.self plus literal static: and nonempty assisted: arrays of direct key paths rooted in that child type.",
            code: .assistedFactoryInvalidArguments
        )
    }

    static func assistedFactoryDuplicateInput() -> Self {
        Self(
            "Each assisted-factory input must appear exactly once across static: and assisted:.",
            code: .assistedFactoryDuplicateInput
        )
    }

    static func assistedFactoryInputPartitionMismatch(
        expectedStatic: [String],
        expectedAssisted: [String]
    ) -> Self {
        Self(
            "@AssistedFactory must partition every child input exactly once. Expected static: [\(expectedStatic.joined(separator: ", "))] and assisted: [\(expectedAssisted.joined(separator: ", "))].",
            code: .assistedFactoryInputPartitionMismatch
        )
    }

    static func assistedFactoryAccessLevelMismatch(
        factoryAccess: String,
        bridgeAccess: String
    ) -> Self {
        Self(
            "@AssistedFactory is \(factoryAccess), but its child/input type bridge is only \(bridgeAccess). Lower the factory access or raise the container and every @Input declaration to the same access level.",
            code: .assistedFactoryAccessLevelMismatch
        )
    }

    static func multibindingInvalidContributors() -> Self {
        Self(
            "@Multibinding requires one literal array of canonical direct-member key paths such as [\\Self.auth, \\Self.logging].",
            code: .multibindingInvalidContributors
        )
    }

    static func multibindingEmptyContributors() -> Self {
        Self(
            "@Multibinding requires at least one contributor.",
            code: .multibindingEmptyContributors
        )
    }

    static func multibindingDuplicateContributor() -> Self {
        Self(
            "Each @Multibinding contributor may appear only once.",
            code: .multibindingDuplicateContributor
        )
    }

    static func multibindingCollectionTypeRequired(memberName: String) -> Self {
        Self(
            "@Multibinding member '\(memberName)' must declare an array type such as [any RequestInterceptor].",
            code: .multibindingCollectionTypeRequired
        )
    }

    static func multibindingUnknownContributor(
        memberName: String,
        contributorName: String
    ) -> Self {
        Self(
            "@Multibinding member '\(memberName)' references unknown direct dependency '\(contributorName)'.",
            code: .multibindingUnknownContributor
        )
    }

    static func multibindingAsyncContributor(
        memberName: String,
        contributorName: String
    ) -> Self {
        Self(
            "@Multibinding member '\(memberName)' cannot synchronously collect async contributor '\(contributorName)'.",
            code: .multibindingAsyncContributor
        )
    }

    static func multibindingTypeMismatch(
        memberName: String,
        contributorName: String,
        expectedType: String,
        actualType: String
    ) -> Self {
        Self(
            "@Multibinding member '\(memberName)' expects contributor type '\(expectedType)', but '\(contributorName)' exposes '\(actualType)'.",
            code: .multibindingTypeMismatch
        )
    }

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

    static func provideEscapedPropertyIdentifier(memberName: String) -> Self {
        Self(
            "@Provide property '\(memberName)' cannot use a backtick-escaped identifier. Rename it to an unescaped Swift identifier so generated storage and graph identities remain canonical.",
            code: .provideEscapedIdentifierUnsupported
        )
    }

    static func provideEscapedFactoryParameter(
        memberName: String,
        parameterName: String
    ) -> Self {
        Self(
            "Factory for @Provide member '\(memberName)' cannot use backtick-escaped parameter '\(parameterName)'. Rename the parameter to an unescaped Swift identifier so dependency lookup remains canonical.",
            code: .provideEscapedIdentifierUnsupported
        )
    }

    static func subEscapedPropertyIdentifier(memberName: String) -> Self {
        Self(
            "@SubContainer property '\(memberName)' cannot use a backtick-escaped identifier. Rename it to an unescaped Swift identifier so generated child storage and override identities remain canonical.",
            code: .subEscapedIdentifierUnsupported
        )
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

    static func provideEscapingInvalidScope(memberName: String) -> Self {
        Self(
            "@Provide member '\(memberName)' may use escaping: true only with the .input scope.",
            code: .provideEscapingInvalidScope
        )
    }

    static func provideEscapingNonFunctionType(memberName: String) -> Self {
        Self(
            "@Provide(.input, escaping: true) member '\(memberName)' must use a non-optional function type or a typealias that resolves to one.",
            code: .provideEscapingNonFunctionType
        )
    }

    static func containerUnsupportedDeclarationKind(name: String, kind: String) -> Self {
        let support = DIContainerDeclarationSupport.unsupportedKind(
            name: name,
            kind: kind
        )
        return Self(
            support.diagnosticMessage ?? "Unsupported @DIContainer declaration.",
            code: .containerUnsupportedDeclarationKind
        )
    }

    static func containerPrivateAccessUnsupported(name: String) -> Self {
        let support = DIContainerDeclarationSupport.privateAccess(name: name)
        return Self(
            support.diagnosticMessage ?? "Unsupported private @DIContainer declaration.",
            code: .containerPrivateAccessUnsupported
        )
    }

    static func containerGenericUnsupported(name: String, contextName: String?) -> Self {
        let support = DIContainerDeclarationSupport.generic(
            name: name,
            contextName: contextName
        )
        return Self(
            support.diagnosticMessage ?? "Unsupported generic @DIContainer declaration.",
            code: .containerGenericUnsupported
        )
    }

    static func containerUnverifiableEnclosingContext(
        name: String,
        extendedType: String
    ) -> Self {
        let support = DIContainerDeclarationSupport.unverifiableEnclosingContext(
            name: name,
            extendedType: extendedType
        )
        return Self(
            support.diagnosticMessage ?? "Unverifiable @DIContainer declaration context.",
            code: .containerUnverifiableEnclosingContext
        )
    }

    static func containerLocalDeclarationUnsupported(
        name: String,
        context: String
    ) -> Self {
        let support = DIContainerDeclarationSupport.localDeclaration(
            name: name,
            context: context
        )
        return Self(
            support.diagnosticMessage ?? "Unsupported local @DIContainer declaration.",
            code: .containerLocalDeclarationUnsupported
        )
    }

    static func provideFactoryConflict() -> Self {
        Self(
            "@Provide cannot include both factory: and asyncFactory: at the same time.",
            code: .provideFactoryConflict
        )
    }

    static func provideConstructionSourceConflict(memberName: String) -> Self {
        Self(
            "@Provide member '\(memberName)' must declare exactly one construction source: factory:, asyncFactory:, Type.self, or a property initializer. Remove the conflicting sources.",
            code: .provideConstructionSourceConflict
        )
    }

    static func provideWithRequiresTypeConstruction(memberName: String) -> Self {
        Self(
            "@Provide member '\(memberName)' may use with: only with the Type.self construction form. Move sibling wiring into named factory closure parameters or use Type.self.",
            code: .provideWithRequiresTypeConstruction
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

    static func provideInvalidWithDependencies(
        memberName: String,
        expectedRoot: String
    ) -> Self {
        Self(
            "@Provide for '\(memberName)' requires with: to be a literal array of canonical direct-member key paths such as [\\\(expectedRoot).config] or []. Use exactly one member component and the Self root.",
            code: .provideInvalidWithDependencies
        )
    }

    static func provideOpaqueTypeUnsupported(memberName: String) -> Self {
        Self(
            "@Provide member '\(memberName)' cannot use an opaque 'some' property type because generated storage and Overrides require a stable optional type. Expose an existential 'any Protocol' instead.",
            code: .provideOpaqueTypeUnsupported
        )
    }

    static func provideIUOTypeUnsupported(memberName: String) -> Self {
        Self(
            "@Provide member '\(memberName)' cannot use an implicitly unwrapped optional type. Replace 'T!' with explicit 'T' or 'T?' so generated storage and sibling wiring have one unambiguous optionality contract.",
            code: .provideIUOTypeUnsupported
        )
    }

    static func provideDuplicateAttribute(memberName: String) -> Self {
        Self(
            "@Provide member '\(memberName)' declares @Provide more than once. Keep exactly one @Provide attribute on each dependency property.",
            code: .provideDuplicateAttribute
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

    static func provideAsyncDependencyRequiresAsyncConsumer(
        memberName: String,
        dependencyName: String,
        providerThrows: Bool
    ) -> Self {
        let requiredClosure = providerThrows ? "an async throws closure" : "an async closure"
        let providerEffect = providerThrows ? "asynchronous and throwing" : "asynchronous"
        return Self(
            "Dependency '\(dependencyName)' used by '\(memberName)' is \(providerEffect). Declare '\(memberName)' with asyncFactory: and \(requiredClosure).",
            code: .provideAsyncDependencyRequiresAsyncConsumer
        )
    }

    static func provideRequiresDirectContainerMember(
        memberName: String
    ) -> Self {
        Self(
            "@Provide member '\(memberName)' must be declared as a direct stored instance var in a supported @DIContainer struct in InnoDI 5.0.",
            code: .provideRequiresDirectContainerMember
        )
    }

    static func provideConditionalDeclarationUnsupported(
        memberName: String
    ) -> Self {
        Self(
            "@Provide member '\(memberName)' cannot be declared inside #if in InnoDI 5.0. Move the declaration outside conditional compilation and branch inside its factory or injected implementation instead.",
            code: .provideConditionalDeclarationUnsupported
        )
    }

    static func provideGeneratedAccessorManualAttachment(
        memberName: String
    ) -> Self {
        Self(
            "@InnoDI._InnoDIProvideAccessor is compiler support for @DIContainer and cannot be attached manually to '\(memberName)'. Remove it and declare @Provide on a direct container member.",
            code: .provideGeneratedAccessorManualAttachment
        )
    }

    static func subConditionalDeclarationUnsupported(
        memberName: String
    ) -> Self {
        Self(
            "@SubContainer member '\(memberName)' cannot be declared inside #if in InnoDI 5.0. Move the declaration outside conditional compilation and branch inside the child container or its injected implementation instead.",
            code: .subConditionalDeclarationUnsupported
        )
    }

    static func subRequiresDirectContainerMember(
        memberName: String
    ) -> Self {
        Self(
            "@SubContainer member '\(memberName)' must be declared as a direct stored instance var in a supported @DIContainer struct in InnoDI 5.0.",
            code: .subRequiresDirectContainerMember
        )
    }

    static func subGeneratedAccessorManualAttachment(
        memberName: String
    ) -> Self {
        Self(
            "@InnoDI._InnoDISubContainerAccessor is compiler support for @DIContainer and cannot be attached manually to '\(memberName)'. Remove it and declare @SubContainer on a direct container member.",
            code: .subGeneratedAccessorManualAttachment
        )
    }

    static func subDuplicateAttribute(memberName: String) -> Self {
        Self(
            "@SubContainer member '\(memberName)' declares @SubContainer more than once. Keep exactly one @SubContainer attribute on each child-container property.",
            code: .subDuplicateAttribute
        )
    }

    static func provideThrowingDependencyRequiresThrowingConsumer(
        memberName: String,
        dependencyName: String
    ) -> Self {
        Self(
            "Dependency '\(dependencyName)' used by '\(memberName)' can throw, but '\(memberName)' uses a non-throwing asyncFactory. Mark its asyncFactory closure async throws.",
            code: .provideThrowingDependencyRequiresThrowingConsumer
        )
    }

    static func provideWithDependencyRequiresSynchronousProvider(
        memberName: String,
        dependencyName: String,
        providerThrows: Bool
    ) -> Self {
        let providerEffect = providerThrows ? "asynchronous and throwing" : "asynchronous"
        return Self(
            "Dependency '\(dependencyName)' used by '\(memberName)' is \(providerEffect). Type.self with: wiring supports synchronous providers only; rewrite '\(memberName)' with asyncFactory: and a named '\(dependencyName)' parameter.",
            code: .provideWithDependencyRequiresSynchronousProvider
        )
    }

    static func swiftUIFeatureRootDuplicateDefault(propertyName: String) -> Self {
        Self(
            "Property '\(propertyName)' can declare at most one default feature root without an alias.",
            code: .swiftUIFeatureRootDuplicateDefault
        )
    }

    static func swiftUIFeatureRootHelperNameConflict(helperName: String) -> Self {
        Self(
            "Generated SwiftUI helper '\(helperName)' would conflict with an existing member or another feature-root helper.",
            code: .swiftUIFeatureRootHelperNameConflict
        )
    }

    static func swiftUIFeatureRootInvalidAlias(alias: String) -> Self {
        Self(
            "Feature-root alias '\(alias)' must be a non-empty Swift identifier.",
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

    static func swiftUIEnvironmentBridgeInvalidEnvironmentKeyPath() -> Self {
        Self(
            "@DIEnvironmentBridge requires 'environment' to be a direct-member key-path literal rooted at EnvironmentValues or SwiftUI.EnvironmentValues, such as \\EnvironmentValues.service.",
            code: .swiftUIEnvironmentBridgeInvalidKeyPath
        )
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

    static func componentEscapedTargetUnsupported(name: String) -> Self {
        Self(
            "@DIComponent target '\(name)' cannot use a backtick-escaped identifier. Rename it to an unescaped Swift identifier so the generated dependency protocol has a canonical name.",
            code: .componentEscapedTargetUnsupported
        )
    }

    static func componentOverridesBuilderRequired() -> Self {
        Self(
            "@DIComponent requires the synthesized Overrides builder from @DIContainer. Rename or remove the user-defined Overrides type; custom Overrides types are unsupported in InnoDI 5.0.",
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

    static func containerMainActorNonisolatedMember(memberName: String) -> Self {
        Self(
            "mainActor: true requires dependency member '\(memberName)' to be main actor-isolated, but it is declared 'nonisolated'.",
            code: .containerMainActorNonisolatedMember
        )
    }

    static func containerRoleTokenRequired() -> Self {
        Self(
            "@DIContainerRole role: requires ContainerRole.local, ContainerRole.component, or ContainerRole.root.",
            code: .containerRoleTokenRequired
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
            MacroBuildDiagnosticContract
                .containerCustomInitUnsupportedMessage,
            code: .containerCustomInitUnsupported
        )
    }

    static func containerUnmanagedStoredProperty(memberName: String) -> Self {
        Self(
            "Stored instance member '\(memberName)' is not managed by @DIContainer. Annotate every stored instance member with @Provide or @SubContainer, or make it a computed or type property, so InnoDI can synthesize a complete initializer in 5.0.",
            code: .containerUnmanagedStoredProperty
        )
    }

    static func containerOverridesNameConflict(kind: String) -> Self {
        Self(
            "A nested 'Overrides' \(kind) is already declared, so @DIContainer cannot synthesize its required override API. Rename the user declaration; custom Overrides types are unsupported in InnoDI 5.0.",
            code: .containerOverridesNameConflict
        )
    }

    static func containerPrewarmNameConflict() -> Self {
        Self(
            "An on-demand @DIContainer synthesizes prewarm(_:), but a direct declaration already uses the name 'prewarm'. Rename that declaration so the generated selective prewarm API remains unambiguous.",
            code: .containerPrewarmNameConflict
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
            MacroBuildDiagnosticContract.subInvalidBindingsMessage(
                memberName: memberName
            ),
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
            MacroBuildDiagnosticContract.subUnknownChildInputMessage(
                memberName: memberName,
                childInputName: childInputName,
                childContainerName: childContainerName
            ),
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
            "Direct container declaration '\(memberName)' uses the reserved generated prefix '\(reservedPrefix)'. Rename the declaration so it does not collide with compiler-authored storage and support symbols.",
            code: .containerReservedNamePrefix
        )
    }

    static func containerReservedModuleName(memberName: String) -> Self {
        Self(
            GeneratedQualifierDiagnosticContract
                .containerReservedModuleNameMessage(
                    declarationName: memberName
                ),
            code: .containerReservedModuleName
        )
    }

    static func swiftUIEnvironmentBridgeReservedModuleName(
        declarationName: String
    ) -> Self {
        Self(
            GeneratedQualifierDiagnosticContract
                .environmentBridgeReservedModuleNameMessage(
                    declarationName: declarationName
                ),
            code: .swiftUIEnvironmentBridgeReservedModuleName
        )
    }

    static func swiftUIEnvironmentBridgeExtensionContextUnsupported() -> Self {
        Self(
            GeneratedQualifierDiagnosticContract
                .environmentBridgeExtensionContextUnsupportedMessage,
            code: .swiftUIEnvironmentBridgeExtensionContextUnsupported
        )
    }

    static func swiftUIEnvironmentBridgeUnsupportedDeclarationKind(
        name: String,
        kind: String
    ) -> Self {
        Self(
            "@DIEnvironmentBridge supports only struct, class, and enum declarations in InnoDI 5.0; '\(name)' is declared as \(kind). Move the environment bridge to a supported nominal type.",
            code: .swiftUIEnvironmentBridgeUnsupportedDeclarationKind
        )
    }

    static func swiftUIEnvironmentBridgePrivateNestedTarget(
        name: String
    ) -> Self {
        Self(
            "@DIEnvironmentBridge cannot synthesize a conformance through private nested lookup component '\(name)' because its generated extension is emitted outside that lexical scope. Use fileprivate or default access.",
            code: .swiftUIEnvironmentBridgePrivateNestedTarget
        )
    }

    static func swiftUIEnvironmentBridgeParameterPackUnsupported() -> Self {
        Self(
            "@DIEnvironmentBridge does not support targets with generic parameter packs in InnoDI 5.0. Use ordinary generic parameters or attach the bridge to a non-generic adapter type.",
            code: .swiftUIEnvironmentBridgeParameterPackUnsupported
        )
    }

    static func swiftUIEnvironmentBridgeGeneratedModifierTypeNameConflict(
        memberName: String
    ) -> Self {
        Self(
            "@DIEnvironmentBridge generates nested modifier type '\(memberName)', but the bridge target already declares a conflicting direct type member with that name. Rename the declaration so the modifier can be synthesized without a Swift redeclaration error.",
            code: .swiftUIEnvironmentBridgeGeneratedNameConflict
        )
    }

    static func swiftUIEnvironmentBridgeGeneratedHelperNameConflict(
        memberName: String
    ) -> Self {
        Self(
            "@DIEnvironmentBridge generates zero-parameter instance helper '\(memberName)', but the bridge target already declares a direct instance variable or zero-parameter instance function with that name. Rename the declaration so the helper can be synthesized without a Swift redeclaration error.",
            code: .swiftUIEnvironmentBridgeGeneratedNameConflict
        )
    }

    static func containerDuplicateMemberName(memberName: String) -> Self {
        Self(
            "@DIContainer declares more than one managed member named '\(memberName)'. Give every @Provide and @SubContainer property a unique name so storage, overrides, and graph identities remain unambiguous.",
            code: .containerDuplicateMemberName
        )
    }

    static func containerGeneratedSymbolCollision(
        conflictingMemberName: String,
        generatedName: String,
        firstMemberName: String
    ) -> Self {
        Self(
            "@DIContainer member '\(conflictingMemberName)' would generate support symbol '\(generatedName)', but earlier managed member '\(firstMemberName)' already claims it. Rename one of the @Provide or @SubContainer properties.",
            code: .containerGeneratedSymbolCollision
        )
    }

    static func provideDuplicateFactoryParameter(
        memberName: String,
        parameterName: String
    ) -> Self {
        Self(
            "Factory for @Provide member '\(memberName)' declares parameter '\(parameterName)' more than once. Give every factory parameter a unique dependency name.",
            code: .provideDuplicateFactoryParameter
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
            "@GenerateMock cannot synthesize this protocol because one or more requirements or protocol features are unsupported: \(listed)\(suffix). Custom global actors, individually actor-isolated requirements, associated types, protocol inheritance other than AnyObject or Sendable, unsupported requirement modifiers, subscripts, rethrows, inout parameters, opaque return types, and generic requirements on Sendable protocols need a hand-written mock until the RFC 0001 support matrix expands.",
            code: .generateMockUnsupportedMember,
            severity: .warning
        )
    }
}
