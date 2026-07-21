import InnoDICore
import InnoDIWorkspaceAnalysis
import SwiftSyntax

// Target-scoped source records and the SwiftSyntax visitor that collect
// generated-qualifier lookup inputs before semantic resolution.
enum QualifierMacroKind: String {
    case container = "@DIContainer"
    case environmentBridge = "@DIEnvironmentBridge"
}

enum QualifierSiteContext: Equatable {
    case supported
    case extensionContext
    case local(context: String)
}

enum QualifierLookupScope: String {
    case sameTargetTopLevel = "same-target-top-level"
    case enclosingNominalMember = "enclosing-nominal-member"
    case matchingExtensionMember = "matching-extension-member"
    case visibleDependency = "visible-dependency"
    case inheritedSuperclassMember = "inherited-superclass-member"
}

struct QualifierMacroSite {
    let kind: QualifierMacroKind
    let declarationName: String
    let targetPath: String?
    let enclosingNominalPaths: [String]
    let usage: GeneratedQualifierUsage
    let context: QualifierSiteContext
    let sourceIdentity: String
    let filePath: String
    let targetID: WorkspaceTargetID?
    let location: ValidationIssueLocation

    var lookupOwnerPaths: Set<String> {
        Set(enclosingNominalPaths + (targetPath.map { [$0] } ?? []))
    }

    var macroCoveredDeclarationPaths: Set<String> {
        lookupOwnerPaths
    }

    func isAffected(
        by shadow: QualifierShadowDeclaration,
        lookupScope: QualifierLookupScope
    ) -> Bool {
        let requirements: Set<GeneratedQualifierRequirement>
        switch lookupScope {
        case .sameTargetTopLevel, .visibleDependency:
            requirements = usage.memberBodies.union(
                usage.fileScopeExtensions
            )
        case .enclosingNominalMember, .matchingExtensionMember,
             .inheritedSuperclassMember:
            requirements = usage.memberBodies
        }
        return requirements.contains { requirement in
            guard requirement.name == shadow.name else { return false }
            switch requirement.namespace {
            case .typeOnly:
                return shadow.namespace == .type
            case .typeOrValue:
                return true
            }
        }
    }

    var hasInheritedQualifierRequirements: Bool {
        !usage.memberBodies.isEmpty
    }
}

enum QualifierNameNamespace: String {
    case value
    case type
}

enum QualifierDeclarationAccess: String {
    case `private`
    case `fileprivate`
    case `internal`
    case package
    case `public`
}

enum QualifierShadowScope: Equatable {
    case file
    case nominal(path: String)
    case `extension`(id: String)
    case local
}

struct QualifierShadowDeclaration {
    let id: String
    let name: String
    let namespace: QualifierNameNamespace
    let declaredPath: [String]?
    let access: QualifierDeclarationAccess
    let spiGroups: Set<String>
    let scope: QualifierShadowScope
    let sourceIdentity: String
    let filePath: String
    let targetID: WorkspaceTargetID?
    let location: ValidationIssueLocation

    func isVisibleFromDependency(
        samePackage: Bool,
        exposure: DependencyExposure
    ) -> Bool {
        guard spiGroups.isEmpty
                || !spiGroups.isDisjoint(with: exposure.spiGroups) else {
            return false
        }
        switch access {
        case .public:
            return true
        case .package:
            return samePackage
        case .internal:
            return exposure.isTestable
        case .private, .fileprivate:
            return false
        }
    }
}

struct TargetScopedNominalType {
    let record: SemanticNominalTypeRecord
    let targetID: WorkspaceTargetID?
}

enum QualifierNominalKind: Equatable {
    case `class`
    case `protocol`
}

struct QualifierInheritanceReference {
    let reference: SemanticTypeReference
    let location: ValidationIssueLocation
}

struct QualifierNominalDeclaration {
    let id: String
    let path: String
    let kind: QualifierNominalKind
    let access: QualifierDeclarationAccess
    let spiGroups: Set<String>
    let scope: QualifierShadowScope
    let firstInheritance: QualifierInheritanceReference?
    let sourceIdentity: String
    let filePath: String
    let targetID: WorkspaceTargetID?
    let moduleName: String?
    let location: ValidationIssueLocation
}

struct TargetScopedTypeAlias {
    let record: SemanticTypeAliasRecord
    let targetID: WorkspaceTargetID?
    let access: QualifierDeclarationAccess
    let spiGroups: Set<String>
    let scope: QualifierShadowScope
    let sourceIdentity: String
    let moduleName: String?
}

struct QualifierExtensionScope {
    let id: String
    let reference: SemanticTypeReference
    let targetID: WorkspaceTargetID?
    let moduleName: String?
    let importedModuleNames: Set<String>
}

struct QualifierImportEntry: Hashable {
    let moduleName: String
    let declarationPath: [String]?
    let isExported: Bool
    let isTestable: Bool
    let spiGroups: Set<String>
}

struct DependencyExposure: Hashable {
    let targetID: WorkspaceTargetID
    let declarationPath: [String]?
    let isTestable: Bool
    let spiGroups: Set<String>

    func exposes(
        _ shadow: QualifierShadowDeclaration,
        resolvedExtensionOwners: [String: String]
    ) -> Bool {
        let shadowPath: [String]?
        if case .extension(let id) = shadow.scope,
           let owner = resolvedExtensionOwners[id] {
            shadowPath = owner.split(separator: ".").map(String.init)
                + [shadow.name]
        } else {
            shadowPath = shadow.declaredPath
        }
        guard let shadowPath else { return false }
        if let declarationPath {
            return shadowPath == declarationPath
        }
        return shadow.scope == .file && shadowPath.count == 1
    }
}
