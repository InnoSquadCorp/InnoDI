import SwiftSyntax

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
}

func deduplicateStrings(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values where seen.insert(value).inserted {
        result.append(value)
    }
    return result
}
