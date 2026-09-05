import InnoDICore
import SwiftSyntax

/// Classifies a factory-parameter dependency edge for cycle detection and
/// code generation.
///
/// - `.hard`: the factory consumes the dependency directly and therefore
///   requires it to be resolvable before the factory runs. Participates in
///   DAG cycle validation as a normal edge.
/// - `.soft`: the factory receives the dependency through a deferred `Lazy<T>`
///   wrapper and does not require the target to be resolved at factory-call
///   time. Excluded from cycle detection and rendered with a dashed style.
/// - `.provider`: the factory receives a `Provider<T>` handle that pumps a
///   fresh instance of a `.transient` target on every call. Like `.soft`, it
///   is excluded from cycle detection; unlike `.soft` the validator requires
///   the target member to have `.transient` scope. Rendered with a dotted
///   style.
enum DependencyKind {
    case hard
    case soft
    case provider
}

/// The construction effect explicitly declared by one `@Provide` member.
///
/// InnoDI intentionally does not infer or promote effects across dependency
/// edges. A consumer must opt into every effect required by its providers so
/// its generated accessor and `Task` failure type remain source-visible and
/// predictable.
enum ProvideConstructionEffect {
    case synchronous
    case asynchronous
    case asynchronousThrowing
}

enum ProvideDependencyEffectMismatch {
    /// A synchronous consumer references an async provider. `providerThrows`
    /// lets the diagnostic recommend the complete `async throws` spelling in
    /// one step when both effects are missing.
    case requiresAsync(providerThrows: Bool)
    /// An async non-throwing consumer references an async throwing provider.
    case requiresThrowing
}

func dependencyEffectMismatch(
    consumer: ProvideConstructionEffect,
    provider: ProvideConstructionEffect
) -> ProvideDependencyEffectMismatch? {
    switch (consumer, provider) {
    case (_, .synchronous),
         (.asynchronous, .asynchronous),
         (.asynchronousThrowing, .asynchronous),
         (.asynchronousThrowing, .asynchronousThrowing):
        return nil
    case (.synchronous, .asynchronous):
        return .requiresAsync(providerThrows: false)
    case (.synchronous, .asynchronousThrowing):
        return .requiresAsync(providerThrows: true)
    case (.asynchronous, .asynchronousThrowing):
        return .requiresThrowing
    }
}

struct ClosureParameterReference {
    let name: String
    let token: TokenSyntax
    /// Type annotation as written at the closure parameter site, when available.
    ///
    /// Populated for full parameter-clause closures (`{ (x: T) in ... }`). `nil`
    /// for shorthand closures (`{ x in ... }`) because Swift does not require
    /// an inline type there. Used by `Lazy<T>` detection and reserved
    /// for future type-aware resolution checks.
    let type: TypeSyntax?
    /// Dependency edge classification populated by `parseClosureParameterNames`.
    /// Written `Lazy<...>` parameters become `.soft`, explicit `Provider<...>`
    /// spellings become `.provider`, and every other parameter is `.hard`.
    /// Shorthand closures lack inline type annotations and therefore default
    /// to `.hard`.
    let kind: DependencyKind

    var lazyWrapperCalleeDescription: String? {
        lazyWrapperCalleeDescriptionForType(type)
    }

    var providerWrapperCalleeDescription: String? {
        providerWrapperCalleeDescriptionForType(type)
    }
}

struct WithDependencyReference {
    let name: String
    /// Source-level anchor used as the diagnostic node. For `with: [\.foo]`
    /// this is the KeyPath expression so per-name diagnostics underline the
    /// offending entry instead of falling back to the whole attribute.
    let anchorExpression: ExprSyntax
}

struct SubContainerBindingReference {
    let childInputName: String
    let parentMemberName: String
    let childKeyPath: KeyPathExprSyntax
    let parentKeyPath: KeyPathExprSyntax
}

struct InvalidSubContainerBindingReference {
    let anchorExpression: ExprSyntax
}

struct FeatureRootMemberModel {
    let rootViewTypeName: String
    let alias: String?
    let propertyName: String
    let anchorSyntax: Syntax

    var helperName: String {
        if let alias, !alias.isEmpty {
            return "\(alias)RootView"
        }
        return "\(propertyName)RootView"
    }
}

/// A member inside a `@DIContainer` annotated with `@SubContainer`. Parallel
/// to `ProvideMemberModel` but carries sub-container-specific metadata: a
/// scope that must be explicit (no default), and the ordered parent names the
/// author wants mapped to the child's `.input` parameters.
struct SubContainerMemberModel {
    /// Position of the source declaration in the container member list.
    ///
    /// Provide and SubContainer models live in separate arrays, so generated
    /// support validation uses this index to restore one deterministic
    /// first-claim-wins order across both member kinds.
    let sourceOrder: Int
    /// Field name on the parent (e.g. `feature`).
    let name: String
    /// Child container type as written (`FeatureContainer`, `FeatureContainer<T>`,
    /// or any `TypeSyntax` expressible at property declaration sites).
    let type: TypeSyntax
    /// Parsed scope. `nil` when the author forgot `scope:` — the validator
    /// emits `sub.scope-required` downstream.
    let scope: SubContainerScopeValue?
    /// Raw scope spelling (`"shared"` / `"transient"` / whatever the author
    /// wrote). Retained so diagnostics can show the exact token.
    let scopeName: String?
    /// Original `scope:` expression syntax as written at the attribute site.
    /// Used to anchor diagnostics to the exact bad scope expression when
    /// parsing succeeds syntactically but not semantically.
    let scopeExpressionSyntax: ExprSyntax?
    /// Parent member names derived from `with: [\.foo, \.bar]`, in order.
    /// Empty either when the author relied on automatic name matching or when
    /// they explicitly wrote an empty same-name subset.
    let parentDependencies: [String]
    /// Whether the source used `with:`.
    let hasWithDependencies: Bool
    /// Whether same-name wiring was omitted, fully parsed, or invalid.
    let sameNameWiring: SubContainerSameNameWiringParseState
    /// Original `with:` expression syntax for invalid-wiring diagnostics.
    let sameNameWiringExpressionSyntax: ExprSyntax?
    /// Explicit child `.input` -> parent member remapping from
    /// `bindings: [(child: \.foo, parent: \.bar)]`.
    let explicitBindings: [SubContainerBindingReference]
    /// Invalid `bindings:` expression or element anchors.
    let invalidBindingReferences: [InvalidSubContainerBindingReference]
    /// Literal parse state for `bindings:`.
    let bindingsParseState: SubContainerBindingsParseState
    /// Original key-path expressions from `with:`. Preserved so validation can
    /// point at the exact unknown parent member rather than the whole
    /// attribute.
    let parentDependencyReferences: [WithDependencyReference]
    /// SwiftUI feature root helpers requested through
    /// `@SubContainer(featureRoot:)` / `featureRoots:`.
    let featureRoots: [FeatureRootMemberModel]
    let attribute: AttributeSyntax
    let bindingSyntax: PatternBindingSyntax

    var overrideClosureName: String {
        "\(name)Overrides"
    }

    var hasExplicitSameNameWiring: Bool {
        if case .parsed = sameNameWiring {
            return true
        }
        return false
    }

    var invalidSameNameWiringLabel: SubContainerSameNameWiringLabel? {
        if case let .invalid(label) = sameNameWiring {
            return label
        }
        return nil
    }

    var hasBindingsArgument: Bool {
        switch bindingsParseState {
        case .omitted:
            return false
        case .parsed, .invalid:
            return true
        }
    }

    var hasInvalidBindings: Bool {
        bindingsParseState.isInvalid
    }

    var invalidBindingAnchorExpression: ExprSyntax? {
        invalidBindingReferences.first?.anchorExpression
    }

    var hasLocallyValidGeneratedPeerConfiguration: Bool {
        guard scope != nil,
              !hasInvalidBindings,
              invalidSameNameWiringLabel == nil,
              !(hasWithDependencies && hasBindingsArgument) else {
            return false
        }
        return true
    }

    func parentReferenceSyntax(for parentName: String) -> ExprSyntax? {
        parentDependencyReferences.first(where: { $0.name == parentName })?.anchorExpression
    }

    func childBindingKeyPathSyntax(for childInputName: String) -> KeyPathExprSyntax? {
        explicitBindings.first(where: { $0.childInputName == childInputName })?.childKeyPath
    }

    func parentBindingKeyPathSyntax(for parentName: String) -> KeyPathExprSyntax? {
        explicitBindings.first(where: { $0.parentMemberName == parentName })?.parentKeyPath
    }
}

struct DIContainerExpansionModel {
    let options: DIContainerAttributeInfo
    let accessLevel: String?
    let members: [ProvideMemberModel]
    let subContainerMembers: [SubContainerMemberModel]

    var sharedMembers: [ProvideMemberModel] {
        members.filter { $0.scope == .shared }
    }

    var asyncSharedMembers: [ProvideMemberModel] {
        sharedMembers.filter(\.isAsyncFactory)
    }

    var syncSharedMembers: [ProvideMemberModel] {
        sharedMembers.filter { !$0.isAsyncFactory }
    }

    var inputMembers: [ProvideMemberModel] {
        members.filter { $0.scope == .input }
    }

    var transientMembers: [ProvideMemberModel] {
        members.filter { $0.scope == .transient }
    }
}

struct ProvideMemberModel {
    /// Position of the source declaration in the container member list.
    ///
    /// Used with the SubContainer source order when validating the shared
    /// generated-support namespace.
    let sourceOrder: Int
    let name: String
    let type: TypeSyntax
    let accessLevel: String?
    let scope: ProvideScope
    let initialization: ProvideInitializationValue
    let inputKind: InputKindValue
    let isMultibinding: Bool
    let factory: ExprSyntax?
    let asyncFactory: ExprSyntax?
    let asyncFactoryIsThrowing: Bool
    let typeExpr: ExprSyntax?
    let initializer: ExprSyntax?
    let escapingInput: Bool
    let escapingParseState: BoolArgumentParseState
    let withDependencies: [String]
    let withDependencyLabels: [String]
    let withDependenciesParseState: KeyPathArrayArgumentParseState
    let withDependencyReferences: [WithDependencyReference]
    let closureDependencies: [String]
    let closureParameterReferences: [ClosureParameterReference]
    let closureHasWildcard: Bool
    let attribute: AttributeSyntax
    let bindingSyntax: PatternBindingSyntax

    var explicitDependencies: [String] {
        deduplicateStrings(withDependencies + closureDependencies)
    }

    var graphDependencyCandidates: [String] {
        explicitDependencies
    }

    var isAsyncFactory: Bool {
        asyncFactory != nil
    }

    var constructionEffect: ProvideConstructionEffect {
        guard isAsyncFactory else { return .synchronous }
        return asyncFactoryIsThrowing ? .asynchronousThrowing : .asynchronous
    }

    /// Local configuration validity excluding sibling lookup/effect rules.
    /// Derived diagnostics must not treat a provider whose own construction
    /// contract is already invalid as a usable effect source.
    var hasLocallyValidConstructionConfiguration: Bool {
        guard initialization == .eager || scope == .shared,
              !(initialization == .onDemand && asyncFactory != nil) else {
            return false
        }
        return InnoDICore.isLocallyValidProvideConstruction(
            binding: bindingSyntax,
            scope: scope,
            factory: factory,
            asyncFactory: asyncFactory,
            typeExpression: typeExpr,
            escaping: escapingInput,
            escapingParseState: escapingParseState,
            withDependenciesParseState: withDependenciesParseState
        )
    }

    /// Closure parameter names whose written type is `Lazy<T>` and therefore
    /// introduce a deferred (soft) dependency edge. Used by the validator to
    /// exclude soft edges from cycle detection and by the code generator to
    /// emit `Lazy<T>({ … })` wrappers at factory call sites.
    var softClosureDependencies: [String] {
        deduplicateStrings(
            closureParameterReferences
                .filter { $0.kind == .soft }
                .map(\.name)
        )
    }

    var softClosureParameterReferences: [ClosureParameterReference] {
        closureParameterReferences.filter { $0.kind == .soft }
    }

    /// Closure parameter names whose written type is `Provider<T>` and
    /// therefore introduce a provider edge — excluded from cycle detection
    /// like soft edges, but constrained by the validator to `.transient`
    /// targets.
    var providerClosureDependencies: [String] {
        deduplicateStrings(
            closureParameterReferences
                .filter { $0.kind == .provider }
                .map(\.name)
        )
    }

    var providerClosureParameterReferences: [ClosureParameterReference] {
        closureParameterReferences.filter { $0.kind == .provider }
    }

    /// Closure parameter names that represent hard (non-lazy, non-provider)
    /// edges — the ones that continue to constrain declaration order and
    /// participate in cycle detection.
    var hardClosureDependencies: [String] {
        deduplicateStrings(
            closureParameterReferences
                .filter { $0.kind == .hard }
                .map(\.name)
        )
    }

    var supportsLazySoftTarget: Bool {
        switch scope {
        case .input:
            return true
        case .shared, .transient:
            return !isAsyncFactory
        }
    }

    var isAssistedInput: Bool {
        scope == .input && inputKind == .assisted
    }

    var assistedFactoryChildType: ExprSyntax? {
        parseProvideArguments(attribute).assistedFactoryChildType
    }
}

extension ProvideArguments {
    var constructionEffect: ProvideConstructionEffect {
        guard asyncFactoryExpr != nil else { return .synchronous }
        return asyncFactoryIsThrowing ? .asynchronousThrowing : .asynchronous
    }
}

func deduplicateStrings(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values where seen.insert(value).inserted {
        result.append(value)
    }
    return result
}
