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

struct ClosureParameterReference {
    let name: String
    let token: TokenSyntax
    /// Type annotation as written at the closure parameter site, when available.
    ///
    /// Populated for full parameter-clause closures (`{ (x: T) in ... }`). `nil`
    /// for shorthand closures (`{ x in ... }`) because Swift does not require
    /// an inline type there. Used by Phase K detection (`Lazy<T>`) and reserved
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
    let keyPath: KeyPathExprSyntax
}

/// A member inside a `@DIContainer` annotated with `@SubContainer`. Parallel
/// to `ProvideMemberModel` but carries sub-container-specific metadata: a
/// scope that must be explicit (no default), and the ordered parent keypath
/// names the author wants mapped to the child's `.input` parameters.
struct SubContainerMemberModel {
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
    /// Parent member names derived from `with: [\.foo, \.bar]`, in order.
    /// Empty when the author relied on automatic name matching.
    let parentDependencies: [String]
    let attribute: AttributeSyntax
    let bindingSyntax: PatternBindingSyntax
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
    let name: String
    let type: TypeSyntax
    let scope: ProvideScope
    let factory: ExprSyntax?
    let asyncFactory: ExprSyntax?
    let asyncFactoryIsThrowing: Bool
    let typeExpr: ExprSyntax?
    let initializer: ExprSyntax?
    let concreteOptIn: Bool
    let withDependencies: [String]
    let withDependencyReferences: [WithDependencyReference]
    let closureDependencies: [String]
    let closureParameterReferences: [ClosureParameterReference]
    let closureHasWildcard: Bool
    let expressionReferences: [String]
    let attribute: AttributeSyntax
    let bindingSyntax: PatternBindingSyntax

    var explicitDependencies: [String] {
        deduplicateStrings(withDependencies + closureDependencies)
    }

    var graphDependencyCandidates: [String] {
        deduplicateStrings(explicitDependencies + expressionReferences)
    }

    var isAsyncFactory: Bool {
        asyncFactory != nil
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
        case .input, .transient:
            return true
        case .shared:
            return !isAsyncFactory
        }
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
