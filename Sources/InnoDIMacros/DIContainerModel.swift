import SwiftSyntax

/// Classifies a factory-parameter dependency edge for cycle detection and
/// code generation.
///
/// - `.hard`: the factory consumes the dependency directly and therefore
///   requires it to be resolvable before the factory runs. Participates in
///   DAG cycle validation as a normal edge.
/// - `.soft`: the factory receives the dependency through a deferred wrapper
///   (currently `Lazy<T>`) and does not require the target to be resolved at
///   factory-call time. Excluded from cycle detection and rendered with a
///   dashed style in the dependency graph.
enum DependencyKind {
    case hard
    case soft
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
    /// Hard or soft edge classification. Populated by
    /// `parseClosureParameterNames` based on whether the parameter's written
    /// type is `Lazy<…>` (soft) or anything else (hard). Shorthand closures
    /// lack inline type annotations and therefore default to `.hard`.
    let kind: DependencyKind
}

struct WithDependencyReference {
    let name: String
    let keyPath: KeyPathExprSyntax
}

struct DIContainerExpansionModel {
    let options: DIContainerAttributeInfo
    let accessLevel: String?
    let members: [ProvideMemberModel]

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

    /// Closure parameter names that represent hard (non-lazy) edges —
    /// the ones that continue to constrain declaration order and participate
    /// in cycle detection.
    var hardClosureDependencies: [String] {
        deduplicateStrings(
            closureParameterReferences
                .filter { $0.kind == .hard }
                .map(\.name)
        )
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
