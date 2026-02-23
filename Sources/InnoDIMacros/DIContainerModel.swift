import SwiftSyntax

struct DIContainerExpansionModel {
    let options: DIContainerAttributeInfo
    let accessLevel: String?
    let members: [ProvideMemberModel]

    var sharedMembers: [ProvideMemberModel] {
        members.filter { $0.scope == .shared }
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
    let typeExpr: ExprSyntax?
    let initializer: ExprSyntax?
    let concreteOptIn: Bool
    let withDependencies: [String]
    let closureDependencies: [String]
    let expressionReferences: [String]
    let attribute: AttributeSyntax
    let bindingSyntax: PatternBindingSyntax

    var explicitDependencies: [String] {
        deduplicateStrings(withDependencies + closureDependencies)
    }

    var graphDependencyCandidates: [String] {
        deduplicateStrings(explicitDependencies + expressionReferences)
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
