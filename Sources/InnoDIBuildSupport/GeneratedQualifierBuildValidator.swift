import InnoDICore
import InnoDIWorkspaceAnalysis
import SwiftSyntax

/// Target-scoped full-source validation for module qualifiers emitted by
/// `@DIContainer` and `@DIEnvironmentBridge`.
///
/// Compiler macro expansion receives a detached annotated declaration. It can
/// validate the target's direct members and lexical binders, but not sibling
/// files, complete enclosing member lists, matching extensions, or declarations
/// imported from a visible dependency. This pass closes exactly those lookup
/// scopes before source compilation.
package enum GeneratedQualifierBuildValidator {
    package static func validate(
        rootPath: String
    ) throws -> ValidationIssueReport {
        validate(snapshot: try loadWorkspaceSourceSnapshot(rootPath: rootPath))
    }

    package static func validate(
        snapshot: WorkspaceSourceSnapshot
    ) -> ValidationIssueReport {
        let manifest = snapshot.analysisManifest
        let moduleNamesByTargetID = Dictionary(
            uniqueKeysWithValues: (manifest?.targets ?? []).map {
                ($0.id, $0.moduleName)
            }
        )
        let scanResults = snapshot.files.map { sourceFile in
            QualifierFileScanResult(
                sourceFile: sourceFile,
                moduleName: sourceFile.targetID.flatMap {
                    moduleNamesByTargetID[$0]
                }
            )
        }
        let primaryTargetID = snapshot.primaryTargetID
        let sites = scanResults
            .flatMap(\.sites)
            .filter { site in
                guard manifest != nil else { return true }
                return site.targetID == primaryTargetID
            }

        var issues = contextIssues(for: sites)
        let supportedSites = sites.filter { $0.context == .supported }
        guard !supportedSites.isEmpty else {
            return ValidationIssueReport(issues: sortedIssues(issues))
        }

        let shadows = scanResults.flatMap(\.shadows)
        let extensions = scanResults.flatMap(\.extensions)
        let nominalDeclarations = scanResults.flatMap(\.nominalDeclarations)
        let typeAliases = scanResults.flatMap(\.typeAliases)
        let nominalTypesByScope = Dictionary(
            grouping: scanResults.flatMap(\.nominalTypes),
            by: { targetScopeKey($0.targetID) }
        )
        let aliasesByScope = Dictionary(
            grouping: scanResults.flatMap(\.typeAliases),
            by: { targetScopeKey($0.targetID) }
        )
        let resolvedExtensionOwners = resolveExtensionOwners(
            extensions: extensions,
            nominalTypesByScope: nominalTypesByScope,
            aliasesByScope: aliasesByScope
        )
        let importsBySourceIdentity = Dictionary(
            uniqueKeysWithValues: scanResults.map {
                ($0.sourceIdentity, $0.imports)
            }
        )
        let exportedImportsByTargetID: [
            WorkspaceTargetID: [QualifierImportEntry]
        ] = scanResults.reduce(into: [:]) { result, scanResult in
            guard let targetID = scanResult.targetID else { return }
            result[targetID, default: []].append(
                contentsOf: scanResult.imports.filter(\.isExported)
            )
        }

        var pending: [PendingQualifierIssueKey: PendingQualifierIssue] = [:]
        var pendingInheritance: [
            PendingInheritanceIssueKey: PendingInheritanceIssue
        ] = [:]
        for site in supportedSites {
            let sameTargetShadows = shadows.filter {
                targetScopeKey($0.targetID) == targetScopeKey(site.targetID)
            }
            for shadow in sameTargetShadows where site.isAffected(by: shadow) {
                guard let lookupScope = lookupScope(
                    of: shadow,
                    from: site,
                    resolvedExtensionOwners: resolvedExtensionOwners
                ) else {
                    continue
                }
                appendPendingIssue(
                    shadow: shadow,
                    site: site,
                    lookupScope: lookupScope,
                    pending: &pending
                )
            }

            let siteExposures: Set<DependencyExposure>
            if let manifest,
               let siteTargetID = site.targetID {
                siteExposures = dependencyExposures(
                    from: siteTargetID,
                    sourceImports: effectiveImports(
                        for: site.sourceIdentity,
                        targetID: siteTargetID,
                        importsBySourceIdentity: importsBySourceIdentity,
                        exportedImportsByTargetID: exportedImportsByTargetID
                    ),
                    manifest: manifest,
                    exportedImportsByTargetID: exportedImportsByTargetID
                )
                for exposure in siteExposures {
                    guard let dependencyTarget = manifest.target(
                        id: exposure.targetID
                    ),
                          let siteTarget = manifest.target(id: siteTargetID) else {
                        continue
                    }
                    for shadow in shadows
                        where shadow.targetID == exposure.targetID {
                        guard shadow.isVisibleFromDependency(
                                samePackage: dependencyTarget.packageIdentity
                                    == siteTarget.packageIdentity,
                                exposure: exposure
                              ),
                              exposure.exposes(
                                shadow,
                                resolvedExtensionOwners: resolvedExtensionOwners
                              ),
                              site.isAffected(by: shadow) else {
                            continue
                        }
                        appendPendingIssue(
                            shadow: shadow,
                            site: site,
                            lookupScope: "visible-dependency",
                            pending: &pending
                        )
                    }
                }
            } else {
                siteExposures = []
            }

            appendInheritedQualifierIssues(
                for: site,
                nominalDeclarations: nominalDeclarations,
                typeAliases: typeAliases,
                shadows: shadows,
                resolvedExtensionOwners: resolvedExtensionOwners,
                manifest: manifest,
                importsBySourceIdentity: importsBySourceIdentity,
                exportedImportsByTargetID: exportedImportsByTargetID,
                siteExposures: siteExposures,
                pendingQualifier: &pending,
                pendingInheritance: &pendingInheritance
            )
        }

        issues.append(contentsOf: pending.values.map(\.issue))
        issues.append(contentsOf: pendingInheritance.values.map(\.issue))
        return ValidationIssueReport(issues: sortedIssues(issues))
    }
}

private enum QualifierMacroKind: String {
    case container = "@DIContainer"
    case environmentBridge = "@DIEnvironmentBridge"
}

private enum QualifierSiteContext: Equatable {
    case supported
    case extensionContext
    case local(context: String)
}

private struct QualifierMacroSite {
    let kind: QualifierMacroKind
    let declarationName: String
    let targetPath: String?
    let enclosingNominalPaths: [String]
    let isContainer: Bool
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

    func isAffected(by shadow: QualifierShadowDeclaration) -> Bool {
        switch kind {
        case .container:
            if shadow.name == "InnoDI" {
                return true
            }
            return shadow.namespace == .type
                && ["Swift", "_Concurrency"].contains(shadow.name)
        case .environmentBridge:
            guard shadow.namespace == .type else { return false }
            let bridgeOwnedNames: Set<String> = isContainer
                ? ["SwiftUI", "InnoDISwiftUI"]
                : ["Swift", "SwiftUI", "InnoDISwiftUI"]
            return bridgeOwnedNames.contains(shadow.name)
        }
    }

    func isAffectedByInheritedShadow(
        _ shadow: QualifierShadowDeclaration
    ) -> Bool {
        switch kind {
        case .container:
            return isAffected(by: shadow)
        case .environmentBridge:
            guard shadow.namespace == .type else { return false }
            let bridgeOwnedNames: Set<String> = isContainer
                ? ["SwiftUI"]
                : ["Swift", "SwiftUI"]
            return bridgeOwnedNames.contains(shadow.name)
        }
    }
}

private enum QualifierNameNamespace: String {
    case value
    case type
}

private enum QualifierDeclarationAccess: String {
    case `private`
    case `fileprivate`
    case `internal`
    case package
    case `public`
}

private enum QualifierShadowScope: Equatable {
    case file
    case nominal(path: String)
    case `extension`(id: String)
    case local
}

private struct QualifierShadowDeclaration {
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

private struct TargetScopedNominalType {
    let record: SemanticNominalTypeRecord
    let targetID: WorkspaceTargetID?
}

private enum QualifierNominalKind: Equatable {
    case `class`
    case `protocol`
}

private struct QualifierInheritanceReference {
    let reference: SemanticTypeReference
    let location: ValidationIssueLocation
}

private struct QualifierNominalDeclaration {
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

private struct TargetScopedTypeAlias {
    let record: SemanticTypeAliasRecord
    let targetID: WorkspaceTargetID?
    let access: QualifierDeclarationAccess
    let spiGroups: Set<String>
    let scope: QualifierShadowScope
    let sourceIdentity: String
    let moduleName: String?
}

private struct QualifierExtensionScope {
    let id: String
    let reference: SemanticTypeReference
    let targetID: WorkspaceTargetID?
    let moduleName: String?
    let importedModuleNames: Set<String>
}

private struct QualifierImportEntry: Hashable {
    let moduleName: String
    let declarationPath: [String]?
    let isExported: Bool
    let isTestable: Bool
    let spiGroups: Set<String>
}

private struct DependencyExposure: Hashable {
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

private struct QualifierFileScanResult {
    let sourceIdentity: String
    let targetID: WorkspaceTargetID?
    let sites: [QualifierMacroSite]
    let shadows: [QualifierShadowDeclaration]
    let extensions: [QualifierExtensionScope]
    let nominalTypes: [TargetScopedNominalType]
    let nominalDeclarations: [QualifierNominalDeclaration]
    let typeAliases: [TargetScopedTypeAlias]
    let imports: [QualifierImportEntry]

    init(
        sourceFile: WorkspaceSourceFile,
        moduleName: String?
    ) {
        let collector = QualifierFileCollector(
            sourceFile: sourceFile,
            moduleName: moduleName
        )
        collector.walk(sourceFile.syntax)
        sourceIdentity = sourceFile.sourceIdentity
        targetID = sourceFile.targetID
        sites = collector.sites
        shadows = collector.shadows
        let importedModuleNames = Set(collector.imports.map(\.moduleName))
        extensions = collector.extensions.map { extensionScope in
            QualifierExtensionScope(
                id: extensionScope.id,
                reference: extensionScope.reference,
                targetID: extensionScope.targetID,
                moduleName: extensionScope.moduleName,
                importedModuleNames: importedModuleNames
            )
        }
        nominalTypes = collector.nominalTypes
        nominalDeclarations = collector.nominalDeclarations
        typeAliases = collector.typeAliases
        imports = Array(Set(collector.imports)).sorted {
            if $0.moduleName != $1.moduleName {
                return $0.moduleName < $1.moduleName
            }
            return ($0.declarationPath ?? []).lexicographicallyPrecedes(
                $1.declarationPath ?? []
            )
        }
    }
}

private struct QualifierExtensionDefaults {
    let access: QualifierDeclarationAccess
    let spiGroups: Set<String>
}

private enum ActiveQualifierScope {
    case nominal(path: String)
    case `extension`(
        id: String,
        reference: SemanticTypeReference,
        defaults: QualifierExtensionDefaults
    )
    case executable(description: String)
}

private final class QualifierFileCollector: SyntaxVisitor {
    private let sourceFile: WorkspaceSourceFile
    private let moduleName: String?
    private let locationConverter: SourceLocationConverter
    private var activeScopes: [ActiveQualifierScope] = []
    private var codeBlockScopePushes: [Bool] = []
    private var switchCaseScopePushes: [Bool] = []

    private(set) var sites: [QualifierMacroSite] = []
    private(set) var shadows: [QualifierShadowDeclaration] = []
    private(set) var extensions: [QualifierExtensionScope] = []
    private(set) var nominalTypes: [TargetScopedNominalType] = []
    private(set) var nominalDeclarations: [QualifierNominalDeclaration] = []
    private(set) var typeAliases: [TargetScopedTypeAlias] = []
    private(set) var imports: [QualifierImportEntry] = []

    init(
        sourceFile: WorkspaceSourceFile,
        moduleName: String?
    ) {
        self.sourceFile = sourceFile
        self.moduleName = moduleName
        self.locationConverter = SourceLocationConverter(
            fileName: sourceFile.filePath,
            tree: sourceFile.syntax
        )
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        visitNominal(node, name: node.name.text, nameToken: node.name)
    }

    override func visitPost(_ node: StructDeclSyntax) {
        activeScopes.removeLast()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        visitNominal(
            node,
            name: node.name.text,
            nameToken: node.name,
            kind: .class,
            inheritanceClause: node.inheritanceClause
        )
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        activeScopes.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        visitNominal(node, name: node.name.text, nameToken: node.name)
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        activeScopes.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        visitNominal(node, name: node.name.text, nameToken: node.name)
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        activeScopes.removeLast()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        visitNominal(
            node,
            name: node.name.text,
            nameToken: node.name,
            kind: .protocol,
            inheritanceClause: node.inheritanceClause
        )
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        activeScopes.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let reference = normalizedQualifierTypeReference(node.extendedType)
            ?? SemanticTypeReference(
                displayPath: node.extendedType.trimmedDescription,
                components: []
            )
        if let attribute = environmentBridgeAttribute(in: node.attributes) {
            sites.append(
                makeSite(
                    kind: .environmentBridge,
                    declarationName: reference.displayPath,
                    targetPath: nil,
                    isContainer: false,
                    context: .extensionContext,
                    attribute: attribute
                )
            )
        }
        let id = "\(sourceFile.sourceIdentity)#extension-\(node.position.utf8Offset)"
        extensions.append(
            QualifierExtensionScope(
                id: id,
                reference: reference,
                targetID: sourceFile.targetID,
                moduleName: moduleName,
                importedModuleNames: []
            )
        )
        activeScopes.append(
            .extension(
                id: id,
                reference: reference,
                defaults: QualifierExtensionDefaults(
                    access: declarationAccess(node.modifiers),
                    spiGroups: spiGroups(in: node.attributes)
                )
            )
        )
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        activeScopes.removeLast()
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTypeShadow(
            nameToken: node.name,
            modifiers: node.modifiers,
            attributes: node.attributes
        )
        let scope = currentDeclarationScope
        if scope != .local,
           let reference = normalizedQualifierTypeReference(
                node.initializer.value
           ) {
            let components = currentSemanticBaseComponents + [node.name.text]
            let visibility = effectiveDeclarationVisibility(
                modifiers: node.modifiers,
                attributes: node.attributes
            )
            typeAliases.append(
                TargetScopedTypeAlias(
                    record: SemanticTypeAliasRecord(
                        path: components.joined(separator: "."),
                        components: components,
                        target: reference
                    ),
                    targetID: sourceFile.targetID,
                    access: visibility.access,
                    spiGroups: visibility.spiGroups,
                    scope: scope,
                    sourceIdentity: sourceFile.sourceIdentity,
                    moduleName: moduleName
                )
            )
        }
        return .skipChildren
    }

    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTypeShadow(
            nameToken: node.name,
            modifiers: node.modifiers,
            attributes: node.attributes
        )
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard currentDeclarationScope != .local else {
            return .visitChildren
        }
        for binding in node.bindings {
            for token in identifierPatternTokens(in: Syntax(binding.pattern)) {
                recordShadow(
                    nameToken: token,
                    namespace: .value,
                    modifiers: node.modifiers,
                    attributes: node.attributes
                )
            }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        recordShadow(
            nameToken: node.name,
            namespace: .value,
            modifiers: node.modifiers,
            attributes: node.attributes
        )
        activeScopes.append(
            .executable(description: "function '\(node.name.text)'")
        )
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        activeScopes.removeLast()
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        for element in node.elements {
            recordShadow(
                nameToken: element.name,
                namespace: .value,
                modifiers: node.modifiers,
                attributes: node.attributes
            )
        }
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        activeScopes.append(.executable(description: "an initializer"))
        return .visitChildren
    }

    override func visitPost(_ node: InitializerDeclSyntax) {
        activeScopes.removeLast()
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        activeScopes.append(.executable(description: "a deinitializer"))
        return .visitChildren
    }

    override func visitPost(_ node: DeinitializerDeclSyntax) {
        activeScopes.removeLast()
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        activeScopes.append(.executable(description: "a subscript"))
        return .visitChildren
    }

    override func visitPost(_ node: SubscriptDeclSyntax) {
        activeScopes.removeLast()
    }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        activeScopes.append(
            .executable(
                description: "a '\(node.accessorSpecifier.text)' accessor"
            )
        )
        return .visitChildren
    }

    override func visitPost(_ node: AccessorDeclSyntax) {
        activeScopes.removeLast()
    }

    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        activeScopes.append(.executable(description: "an accessor"))
        return .visitChildren
    }

    override func visitPost(_ node: AccessorBlockSyntax) {
        activeScopes.removeLast()
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        activeScopes.append(.executable(description: "a closure"))
        return .visitChildren
    }

    override func visitPost(_ node: ClosureExprSyntax) {
        activeScopes.removeLast()
    }

    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        let shouldPush = !hasExecutableScope
        codeBlockScopePushes.append(shouldPush)
        if shouldPush {
            activeScopes.append(.executable(description: "a code block"))
        }
        return .visitChildren
    }

    override func visitPost(_ node: CodeBlockSyntax) {
        if codeBlockScopePushes.removeLast() {
            activeScopes.removeLast()
        }
    }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        let shouldPush = !hasExecutableScope
        switchCaseScopePushes.append(shouldPush)
        if shouldPush {
            activeScopes.append(.executable(description: "a switch case"))
        }
        return .visitChildren
    }

    override func visitPost(_ node: SwitchCaseSyntax) {
        if switchCaseScopePushes.removeLast() {
            activeScopes.removeLast()
        }
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let components = node.path.map { $0.name.text }
        guard let moduleName = components.first else {
            return .skipChildren
        }
        let isExported = node.attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else {
                return false
            }
            return attribute.attributeName.trimmedDescription == "_exported"
        } || node.modifiers.contains { $0.name.text == "public" }
        let isTestable = hasAttribute(
            named: "testable",
            in: node.attributes
        )
        imports.append(
            QualifierImportEntry(
                moduleName: moduleName,
                declarationPath: node.importKindSpecifier == nil
                    ? nil
                    : Array(components.dropFirst()),
                isExported: isExported,
                isTestable: isTestable,
                spiGroups: spiGroups(in: node.attributes)
            )
        )
        return .skipChildren
    }

    private func visitNominal(
        _ node: some DeclGroupSyntax,
        name: String,
        nameToken: TokenSyntax,
        kind: QualifierNominalKind? = nil,
        inheritanceClause: InheritanceClauseSyntax? = nil
    ) -> SyntaxVisitorContinueKind {
        let components = currentSemanticBaseComponents + [name]
        let path = components.joined(separator: ".")
        let declarationScope = currentDeclarationScope
        if let kind,
           declarationScope != .local {
            let visibility = effectiveDeclarationVisibility(
                modifiers: declarationModifiers(node),
                attributes: node.attributes
            )
            let firstInheritance: QualifierInheritanceReference? = if kind == .class,
                                      let inheritedType = inheritanceClause?
                                        .inheritedTypes
                                        .first?
                                        .type {
                QualifierInheritanceReference(
                    reference: normalizedQualifierInheritanceReference(
                        inheritedType
                    ) ?? SemanticTypeReference(
                        displayPath: inheritedType.trimmedDescription,
                        components: []
                    ),
                    location: sourceLocation(
                        for: inheritedType.positionAfterSkippingLeadingTrivia
                    )
                )
            } else {
                nil
            }
            nominalDeclarations.append(
                QualifierNominalDeclaration(
                    id: "\(sourceFile.sourceIdentity)#nominal-\(nameToken.position.utf8Offset)",
                    path: path,
                    kind: kind,
                    access: visibility.access,
                    spiGroups: visibility.spiGroups,
                    scope: declarationScope,
                    firstInheritance: firstInheritance,
                    sourceIdentity: sourceFile.sourceIdentity,
                    filePath: sourceFile.filePath,
                    targetID: sourceFile.targetID,
                    moduleName: moduleName,
                    location: sourceLocation(
                        for: nameToken.positionAfterSkippingLeadingTrivia
                    )
                )
            )
        }
        recordTypeShadow(
            nameToken: nameToken,
            modifiers: declarationModifiers(node),
            attributes: node.attributes
        )
        nominalTypes.append(
            TargetScopedNominalType(
                record: SemanticNominalTypeRecord(
                    path: path,
                    components: components
                ),
                targetID: sourceFile.targetID
            )
        )

        let containerAttribute = findInnoDIAttribute(
            named: "DIContainer",
            in: node.attributes
        )
        let containerSupport = containerAttribute.map { _ in
            classifyDIContainerDeclaration(node)
        }
        if let attribute = containerAttribute,
           containerSupport?.isSupported == true {
            sites.append(
                makeSite(
                    kind: .container,
                    declarationName: name,
                    targetPath: path,
                    isContainer: true,
                    context: .supported,
                    attribute: attribute
                )
            )
        }

        if let attribute = environmentBridgeAttribute(in: node.attributes),
           node.is(StructDeclSyntax.self)
                || node.is(ClassDeclSyntax.self)
                || node.is(EnumDeclSyntax.self),
           containerAttribute == nil || containerSupport?.isSupported == true {
            let context: QualifierSiteContext
            if activeScopes.contains(where: { scope in
                if case .extension = scope { return true }
                return false
            }) {
                context = .extensionContext
            } else if let localContext = activeScopes.reversed().compactMap({
                scope -> String? in
                if case .executable(let description) = scope {
                    return description
                }
                return nil
            }).first {
                context = .local(context: localContext)
            } else {
                context = .supported
            }
            sites.append(
                makeSite(
                    kind: .environmentBridge,
                    declarationName: name,
                    targetPath: path,
                    isContainer: containerAttribute != nil,
                    context: context,
                    attribute: attribute
                )
            )
        }

        activeScopes.append(.nominal(path: path))
        return .visitChildren
    }

    private func makeSite(
        kind: QualifierMacroKind,
        declarationName: String,
        targetPath: String?,
        isContainer: Bool,
        context: QualifierSiteContext,
        attribute: AttributeSyntax
    ) -> QualifierMacroSite {
        QualifierMacroSite(
            kind: kind,
            declarationName: declarationName,
            targetPath: targetPath,
            enclosingNominalPaths: activeScopes.compactMap { scope in
                if case .nominal(let path) = scope { return path }
                return nil
            },
            isContainer: isContainer,
            context: context,
            sourceIdentity: sourceFile.sourceIdentity,
            filePath: sourceFile.filePath,
            targetID: sourceFile.targetID,
            location: sourceLocation(for: attribute.positionAfterSkippingLeadingTrivia)
        )
    }

    private var currentSemanticBaseComponents: [String] {
        if let path = activeScopes.reversed().compactMap({ scope -> String? in
            if case .nominal(let path) = scope { return path }
            return nil
        }).first {
            return path.split(separator: ".").map(String.init)
        }
        if let reference = activeScopes.reversed().compactMap({
            scope -> SemanticTypeReference? in
            if case .extension(_, let reference, _) = scope {
                return reference
            }
            return nil
        }).first {
            return reference.components
        }
        return []
    }

    private var currentDeclarationScope: QualifierShadowScope {
        if hasExecutableScope {
            return .local
        }
        for scope in activeScopes.reversed() {
            switch scope {
            case .nominal(let path):
                return .nominal(path: path)
            case .extension(let id, _, _):
                return .extension(id: id)
            case .executable:
                return .local
            }
        }
        return .file
    }

    private var hasExecutableScope: Bool {
        activeScopes.contains { scope in
            if case .executable = scope { return true }
            return false
        }
    }

    private var currentExtensionDefaults: QualifierExtensionDefaults? {
        guard case .extension = currentDeclarationScope else {
            return nil
        }
        return activeScopes.reversed().compactMap { scope in
            if case .extension(_, _, let defaults) = scope {
                return defaults
            }
            return nil
        }.first
    }

    private func recordTypeShadow(
        nameToken: TokenSyntax,
        modifiers: DeclModifierListSyntax,
        attributes: AttributeListSyntax?
    ) {
        recordShadow(
            nameToken: nameToken,
            namespace: .type,
            modifiers: modifiers,
            attributes: attributes
        )
    }

    private func recordShadow(
        nameToken: TokenSyntax,
        namespace: QualifierNameNamespace,
        modifiers: DeclModifierListSyntax,
        attributes: AttributeListSyntax?
    ) {
        let scope = currentDeclarationScope
        guard scope != .local else { return }
        let name = unescapedIdentifier(nameToken.text)
        let ownerComponents: [String]
        switch scope {
        case .file:
            ownerComponents = []
        case .nominal(let path):
            ownerComponents = path.split(separator: ".").map(String.init)
        case .extension, .local:
            ownerComponents = []
        }
        let location = sourceLocation(
            for: nameToken.positionAfterSkippingLeadingTrivia
        )
        let visibility = effectiveDeclarationVisibility(
            modifiers: modifiers,
            attributes: attributes
        )
        shadows.append(
            QualifierShadowDeclaration(
                id: "\(sourceFile.sourceIdentity)#\(nameToken.position.utf8Offset)#\(namespace.rawValue)",
                name: name,
                namespace: namespace,
                declaredPath: namespace == .type
                    ? ownerComponents + [name]
                    : (scope == .file ? [name] : nil),
                access: visibility.access,
                spiGroups: visibility.spiGroups,
                scope: scope,
                sourceIdentity: sourceFile.sourceIdentity,
                filePath: sourceFile.filePath,
                targetID: sourceFile.targetID,
                location: location
            )
        )
    }

    private func effectiveDeclarationVisibility(
        modifiers: DeclModifierListSyntax,
        attributes: AttributeListSyntax?
    ) -> QualifierExtensionDefaults {
        let extensionDefaults = currentExtensionDefaults
        let declaredSPIGroups = spiGroups(in: attributes)
        return QualifierExtensionDefaults(
            access: declarationAccess(
                modifiers,
                defaultAccess: extensionDefaults?.access ?? .internal
            ),
            spiGroups: declaredSPIGroups.isEmpty
                ? (extensionDefaults?.spiGroups ?? [])
                : declaredSPIGroups
        )
    }

    private func sourceLocation(
        for position: AbsolutePosition
    ) -> ValidationIssueLocation {
        let location = locationConverter.location(for: position)
        return ValidationIssueLocation(
            filePath: sourceFile.filePath,
            line: location.line,
            column: location.column
        )
    }
}

private struct PendingQualifierIssueKey: Hashable {
    let code: String
    let shadowID: String
}

private struct PendingQualifierIssue {
    let code: String
    let message: String
    let shadow: QualifierShadowDeclaration
    var lookupScopes: Set<String>
    var sitesByIdentity: [String: QualifierMacroSite]

    var issue: ValidationIssue {
        let sites = sitesByIdentity.values.sorted {
            if $0.filePath != $1.filePath { return $0.filePath < $1.filePath }
            if $0.location.line != $1.location.line {
                return $0.location.line < $1.location.line
            }
            return $0.location.column < $1.location.column
        }
        return ValidationIssue(
            code: code,
            severity: .error,
            message: message,
            location: shadow.location,
            notes: sites.map { site in
                ValidationIssueNote(
                    message: "affected \(site.kind.rawValue) target '\(site.targetPath ?? site.declarationName)' is declared here.",
                    location: site.location
                )
            },
            remediation: "Rename '\(shadow.name)' so generated module-qualified references remain unambiguous.",
            metadata: [
                "affectedSiteCount": String(sites.count),
                "lookupScopes": lookupScopes.sorted().joined(separator: ","),
                "qualifier": shadow.name,
            ]
        )
    }
}

private struct PendingInheritanceIssueKey: Hashable {
    let classID: String
    let resolutionState: SemanticResolutionState
}

private struct PendingInheritanceIssue {
    let declaration: QualifierNominalDeclaration
    let inheritance: QualifierInheritanceReference
    let resolutionState: SemanticResolutionState
    var sitesByIdentity: [String: QualifierMacroSite]

    var issue: ValidationIssue {
        let sites = sitesByIdentity.values.sorted(by: qualifierSiteSortOrder)
        return ValidationIssue(
            code: GeneratedQualifierDiagnosticContract
                .inheritanceUnverifiableCode,
            severity: .error,
            message: GeneratedQualifierDiagnosticContract
                .inheritanceUnverifiableMessage(
                    className: declaration.path,
                    inheritedType: inheritance.reference.displayPath,
                    resolutionState: resolutionState.rawValue
                ),
            location: inheritance.location,
            notes: sites.map { site in
                ValidationIssueNote(
                    message: "affected \(site.kind.rawValue) target '\(site.targetPath ?? site.declarationName)' is declared here.",
                    location: site.location
                )
            },
            remediation: "Make the superclass or protocol declaration and any typealias chain source-visible to InnoDI's target-scoped build preflight.",
            metadata: [
                "affectedSiteCount": String(sites.count),
                "class": declaration.path,
                "inheritedType": inheritance.reference.displayPath,
                "resolutionState": resolutionState.rawValue,
            ]
        )
    }
}

private func qualifierSiteSortOrder(
    _ lhs: QualifierMacroSite,
    _ rhs: QualifierMacroSite
) -> Bool {
    if lhs.filePath != rhs.filePath { return lhs.filePath < rhs.filePath }
    if lhs.location.line != rhs.location.line {
        return lhs.location.line < rhs.location.line
    }
    return lhs.location.column < rhs.location.column
}

private func appendPendingIssue(
    shadow: QualifierShadowDeclaration,
    site: QualifierMacroSite,
    lookupScope: String,
    pending: inout [PendingQualifierIssueKey: PendingQualifierIssue]
) {
    let code: String
    let message: String
    switch site.kind {
    case .container:
        code = GeneratedQualifierDiagnosticContract
            .containerReservedModuleNameCode
        message = GeneratedQualifierDiagnosticContract
            .containerReservedModuleNameMessage(
                declarationName: shadow.name
            )
    case .environmentBridge:
        code = GeneratedQualifierDiagnosticContract
            .environmentBridgeReservedModuleNameCode
        message = GeneratedQualifierDiagnosticContract
            .environmentBridgeReservedModuleNameMessage(
                declarationName: shadow.name
            )
    }
    let key = PendingQualifierIssueKey(code: code, shadowID: shadow.id)
    let siteIdentity = "\(site.sourceIdentity)#\(site.location.line):\(site.location.column)#\(site.kind.rawValue)"
    if var existing = pending[key] {
        existing.lookupScopes.insert(lookupScope)
        existing.sitesByIdentity[siteIdentity] = site
        pending[key] = existing
    } else {
        pending[key] = PendingQualifierIssue(
            code: code,
            message: message,
            shadow: shadow,
            lookupScopes: [lookupScope],
            sitesByIdentity: [siteIdentity: site]
        )
    }
}

private func lookupScope(
    of shadow: QualifierShadowDeclaration,
    from site: QualifierMacroSite,
    resolvedExtensionOwners: [String: String]
) -> String? {
    if let declaredPath = shadow.declaredPath?.joined(separator: "."),
       site.macroCoveredDeclarationPaths.contains(declaredPath) {
        return nil
    }
    switch shadow.scope {
    case .file:
        guard shadow.access != .private && shadow.access != .fileprivate
                || shadow.sourceIdentity == site.sourceIdentity else {
            return nil
        }
        return "same-target-top-level"
    case .nominal(let path):
        guard site.lookupOwnerPaths.contains(path),
              path != site.targetPath else {
            // Direct target members remain owned by the attached macro.
            return nil
        }
        return "enclosing-nominal-member"
    case .extension(let id):
        guard let owner = resolvedExtensionOwners[id],
              site.lookupOwnerPaths.contains(owner),
              shadow.access != .private && shadow.access != .fileprivate
                || shadow.sourceIdentity == site.sourceIdentity else {
            return nil
        }
        return "matching-extension-member"
    case .local:
        return nil
    }
}

private func resolveExtensionOwners(
    extensions: [QualifierExtensionScope],
    nominalTypesByScope: [String: [TargetScopedNominalType]],
    aliasesByScope: [String: [TargetScopedTypeAlias]]
) -> [String: String] {
    var result: [String: String] = [:]
    for extensionScope in extensions {
        let key = targetScopeKey(extensionScope.targetID)
        let nominalTypes = nominalTypesByScope[key, default: []].map(\.record)
        let aliases = aliasesByScope[key, default: []].map(\.record)
        let resolver = SemanticResolverIndex(
            nominalTypes: nominalTypes,
            topLevelTypeAliases: aliases
        )
        let resolution = resolver.resolvePath(
            for: extensionScope.reference,
            candidatePaths: Set(nominalTypes.map(\.path))
        )
        if resolution.state == .resolved,
           let path = resolution.resolvedPath {
            result[extensionScope.id] = path
            continue
        }
        guard resolution.state == .unresolved else {
            continue
        }

        // Preserve an exact nested-type interpretation first. Only after it
        // fails do we strip a known self-module prefix from the extension and
        // alias targets. Root-path mode has no module identity, so the same
        // suffix attempt is deliberately conservative.
        let fallbackReference = droppingQualifierModulePrefix(
            from: extensionScope.reference,
            moduleName: extensionScope.moduleName,
            importedModuleNames: extensionScope.importedModuleNames
        ) ?? extensionScope.reference
        let fallbackAliases = aliases.map { alias in
            SemanticTypeAliasRecord(
                path: alias.path,
                components: alias.components,
                target: droppingQualifierModulePrefix(
                    from: alias.target,
                    moduleName: extensionScope.moduleName,
                    importedModuleNames: extensionScope.importedModuleNames
                ) ?? alias.target
            )
        }
        guard fallbackReference != extensionScope.reference
                || fallbackAliases != aliases else {
            continue
        }
        let fallbackResolver = SemanticResolverIndex(
            nominalTypes: nominalTypes,
            topLevelTypeAliases: fallbackAliases
        )
        let fallback = fallbackResolver.resolvePath(
            for: fallbackReference,
            candidatePaths: Set(nominalTypes.map(\.path))
        )
        if fallback.state == .resolved,
           let path = fallback.resolvedPath {
            result[extensionScope.id] = path
        }
    }
    return result
}

private func droppingQualifierModulePrefix(
    from reference: SemanticTypeReference,
    moduleName: String?,
    importedModuleNames: Set<String> = []
) -> SemanticTypeReference? {
    guard reference.components.count > 1 else {
        return nil
    }
    if let moduleName,
       reference.components.first != moduleName {
        return nil
    }
    if moduleName == nil,
       let first = reference.components.first,
       importedModuleNames.contains(first) {
        return nil
    }
    let components = Array(reference.components.dropFirst())
    return SemanticTypeReference(
        displayPath: components.joined(separator: "."),
        components: components
    )
}

private func effectiveImports(
    for sourceIdentity: String,
    targetID: WorkspaceTargetID,
    importsBySourceIdentity: [String: [QualifierImportEntry]],
    exportedImportsByTargetID: [
        WorkspaceTargetID: [QualifierImportEntry]
    ]
) -> [QualifierImportEntry] {
    // Exported imports contribute their public/package surface to sibling
    // files, but source-local @testable and @_spi capabilities do not cross
    // that file boundary.
    let moduleWideExports = exportedImportsByTargetID[
        targetID,
        default: []
    ].map { entry in
        QualifierImportEntry(
            moduleName: entry.moduleName,
            declarationPath: entry.declarationPath,
            isExported: true,
            isTestable: false,
            spiGroups: []
        )
    }
    return (importsBySourceIdentity[sourceIdentity] ?? [])
        + moduleWideExports
}

private func dependencyExposures(
    from siteTargetID: WorkspaceTargetID,
    sourceImports: [QualifierImportEntry],
    manifest: WorkspaceAnalysisManifest,
    exportedImportsByTargetID: [WorkspaceTargetID: [QualifierImportEntry]]
) -> Set<DependencyExposure> {
    guard let siteTarget = manifest.target(id: siteTargetID) else {
        return []
    }
    let targetsByModuleName = Dictionary(
        grouping: manifest.targets,
        by: \.moduleName
    )
    var exposures: Set<DependencyExposure> = []
    var pending: [DependencyExposure] = []

    func appendImports(
        _ imports: [QualifierImportEntry],
        from target: WorkspaceAnalysisTarget,
        propagatedVisibility: (
            isTestable: Bool,
            spiGroups: Set<String>
        )? = nil
    ) {
        let directDependencies = Set(target.directDependencyTargetIDs)
        for entry in imports {
            for dependency in targetsByModuleName[entry.moduleName, default: []]
                where directDependencies.contains(dependency.id) {
                let exposure = DependencyExposure(
                    targetID: dependency.id,
                    declarationPath: entry.declarationPath,
                    isTestable: propagatedVisibility?.isTestable
                        ?? entry.isTestable,
                    spiGroups: propagatedVisibility?.spiGroups
                        ?? entry.spiGroups
                )
                if exposures.insert(exposure).inserted {
                    pending.append(exposure)
                }
            }
        }
    }

    appendImports(sourceImports, from: siteTarget)
    while let exposure = pending.popLast() {
        // Selective imports do not inherit a dependency module's re-exports.
        guard exposure.declarationPath == nil,
              let dependencyTarget = manifest.target(id: exposure.targetID) else {
            continue
        }
        appendImports(
            exportedImportsByTargetID[exposure.targetID, default: []],
            from: dependencyTarget,
            // A client's SPI capability flows through a re-export chain;
            // @testable access never does. Attributes written on the
            // intermediate export govern that source file, not its clients.
            propagatedVisibility: (
                isTestable: false,
                spiGroups: exposure.spiGroups
            )
        )
    }
    return exposures
}

private struct VisibleInheritanceNominal {
    let resolutionPath: String
    let declaration: QualifierNominalDeclaration
}

private struct VisibleInheritanceAlias {
    let record: SemanticTypeAliasRecord
    let isSameTarget: Bool
}

private enum InheritanceTargetResolution {
    case resolved(QualifierNominalDeclaration)
    case unverifiable(SemanticResolutionState)
}

private func appendInheritedQualifierIssues(
    for site: QualifierMacroSite,
    nominalDeclarations: [QualifierNominalDeclaration],
    typeAliases: [TargetScopedTypeAlias],
    shadows: [QualifierShadowDeclaration],
    resolvedExtensionOwners: [String: String],
    manifest: WorkspaceAnalysisManifest?,
    importsBySourceIdentity: [String: [QualifierImportEntry]],
    exportedImportsByTargetID: [
        WorkspaceTargetID: [QualifierImportEntry]
    ],
    siteExposures: Set<DependencyExposure>,
    pendingQualifier: inout [
        PendingQualifierIssueKey: PendingQualifierIssue
    ],
    pendingInheritance: inout [
        PendingInheritanceIssueKey: PendingInheritanceIssue
    ]
) {
    let startingClasses = nominalDeclarations
        .filter { declaration in
            declaration.kind == .class
                && targetScopeKey(declaration.targetID)
                    == targetScopeKey(site.targetID)
                && site.lookupOwnerPaths.contains(declaration.path)
        }
        .sorted { lhs, rhs in
            if lhs.path != rhs.path { return lhs.path < rhs.path }
            return lhs.id < rhs.id
        }

    for startingClass in startingClasses {
        var currentClass = startingClass
        var visitedClassIDs: Set<String> = []

        inheritanceChain: while visitedClassIDs.insert(currentClass.id).inserted {
            guard let inheritance = currentClass.firstInheritance else {
                break
            }
            let resolution = resolveFirstInheritance(
                of: currentClass,
                inheritance: inheritance,
                nominalDeclarations: nominalDeclarations,
                typeAliases: typeAliases,
                manifest: manifest,
                importsBySourceIdentity: importsBySourceIdentity,
                exportedImportsByTargetID: exportedImportsByTargetID
            )
            switch resolution {
            case .unverifiable(let state):
                appendPendingInheritanceIssue(
                    declaration: currentClass,
                    inheritance: inheritance,
                    resolutionState: state,
                    site: site,
                    pending: &pendingInheritance
                )
                break inheritanceChain
            case .resolved(let inheritedDeclaration):
                guard inheritedDeclaration.kind == .class else {
                    // A source-visible first protocol means there is no
                    // superclass chain to inspect.
                    break inheritanceChain
                }
                for shadow in shadows
                    where shadow.targetID == inheritedDeclaration.targetID {
                    guard isInheritedMember(
                            shadow,
                            of: inheritedDeclaration,
                            resolvedExtensionOwners: resolvedExtensionOwners
                          ),
                          isInheritedShadowVisible(
                            shadow,
                            from: site,
                            manifest: manifest,
                            siteExposures: siteExposures
                          ),
                          site.isAffectedByInheritedShadow(shadow) else {
                        continue
                    }
                    appendPendingIssue(
                        shadow: shadow,
                        site: site,
                        lookupScope: "inherited-superclass-member",
                        pending: &pendingQualifier
                    )
                }
                currentClass = inheritedDeclaration
            }
        }
    }
}

private func appendPendingInheritanceIssue(
    declaration: QualifierNominalDeclaration,
    inheritance: QualifierInheritanceReference,
    resolutionState: SemanticResolutionState,
    site: QualifierMacroSite,
    pending: inout [
        PendingInheritanceIssueKey: PendingInheritanceIssue
    ]
) {
    let key = PendingInheritanceIssueKey(
        classID: declaration.id,
        resolutionState: resolutionState
    )
    let siteIdentity = "\(site.sourceIdentity)#\(site.location.line):\(site.location.column)#\(site.kind.rawValue)"
    if var existing = pending[key] {
        existing.sitesByIdentity[siteIdentity] = site
        pending[key] = existing
    } else {
        pending[key] = PendingInheritanceIssue(
            declaration: declaration,
            inheritance: inheritance,
            resolutionState: resolutionState,
            sitesByIdentity: [siteIdentity: site]
        )
    }
}

private func resolveFirstInheritance(
    of declaration: QualifierNominalDeclaration,
    inheritance: QualifierInheritanceReference,
    nominalDeclarations: [QualifierNominalDeclaration],
    typeAliases: [TargetScopedTypeAlias],
    manifest: WorkspaceAnalysisManifest?,
    importsBySourceIdentity: [String: [QualifierImportEntry]],
    exportedImportsByTargetID: [
        WorkspaceTargetID: [QualifierImportEntry]
    ]
) -> InheritanceTargetResolution {
    let exposures: Set<DependencyExposure>
    if let manifest,
       let targetID = declaration.targetID {
        exposures = dependencyExposures(
            from: targetID,
            sourceImports: effectiveImports(
                for: declaration.sourceIdentity,
                targetID: targetID,
                importsBySourceIdentity: importsBySourceIdentity,
                exportedImportsByTargetID: exportedImportsByTargetID
            ),
            manifest: manifest,
            exportedImportsByTargetID: exportedImportsByTargetID
        )
    } else {
        exposures = []
    }

    let visibleNominals = visibleInheritanceNominals(
        from: declaration,
        declarations: nominalDeclarations,
        exposures: exposures,
        manifest: manifest
    )
    let visibleAliases = visibleInheritanceAliases(
        from: declaration,
        aliases: typeAliases,
        exposures: exposures,
        manifest: manifest
    )
    let declarationsByResolutionPath = Dictionary(
        grouping: visibleNominals,
        by: \.resolutionPath
    )
    let nominalRecords = declarationsByResolutionPath.keys.sorted().map {
        path in
        SemanticNominalTypeRecord(
            path: path,
            components: path.split(separator: ".").map(String.init)
        )
    }

    func mappedResolution(
        reference: SemanticTypeReference,
        aliases: [SemanticTypeAliasRecord]
    ) -> InheritanceTargetResolution {
        let result = SemanticResolverIndex(
            nominalTypes: nominalRecords,
            topLevelTypeAliases: aliases
        ).resolvePath(
            for: reference,
            candidatePaths: Set(declarationsByResolutionPath.keys)
        )
        guard result.state == .resolved,
              let path = result.resolvedPath else {
            let state = result.state == .excluded
                ? SemanticResolutionState.unresolved
                : result.state
            return .unverifiable(state)
        }
        let declarations = Dictionary(
            uniqueKeysWithValues: declarationsByResolutionPath[
                path,
                default: []
            ].map { ($0.declaration.id, $0.declaration) }
        ).values
        guard declarations.count == 1,
              let resolved = declarations.first else {
            return .unverifiable(.ambiguous)
        }
        return .resolved(resolved)
    }

    let rawAliases = visibleAliases.map(\.record)
    let rawResolution = mappedResolution(
        reference: inheritance.reference,
        aliases: rawAliases
    )
    if case .unverifiable(.unresolved) = rawResolution {
        let fallbackReference = droppingQualifierModulePrefix(
            from: inheritance.reference,
            moduleName: declaration.moduleName
        ) ?? inheritance.reference
        let fallbackAliases = visibleAliases.map { alias in
            guard alias.isSameTarget else { return alias.record }
            return SemanticTypeAliasRecord(
                path: alias.record.path,
                components: alias.record.components,
                target: droppingQualifierModulePrefix(
                    from: alias.record.target,
                    moduleName: declaration.moduleName
                ) ?? alias.record.target
            )
        }
        if fallbackReference != inheritance.reference
            || fallbackAliases != rawAliases {
            return mappedResolution(
                reference: fallbackReference,
                aliases: fallbackAliases
            )
        }
    }
    return rawResolution
}

private func visibleInheritanceNominals(
    from declaration: QualifierNominalDeclaration,
    declarations: [QualifierNominalDeclaration],
    exposures: Set<DependencyExposure>,
    manifest: WorkspaceAnalysisManifest?
) -> [VisibleInheritanceNominal] {
    var result: [VisibleInheritanceNominal] = []
    for candidate in declarations {
        if targetScopeKey(candidate.targetID)
            == targetScopeKey(declaration.targetID) {
            guard isSameTargetDeclarationVisible(
                access: candidate.access,
                sourceIdentity: candidate.sourceIdentity,
                fromSourceIdentity: declaration.sourceIdentity
            ) else {
                continue
            }
            result.append(
                VisibleInheritanceNominal(
                    resolutionPath: candidate.path,
                    declaration: candidate
                )
            )
            continue
        }

        guard let manifest,
              let candidateTargetID = candidate.targetID,
              let declarationTargetID = declaration.targetID,
              let candidateTarget = manifest.target(id: candidateTargetID),
              let declarationTarget = manifest.target(id: declarationTargetID),
              exposures.contains(where: { exposure in
                  exposure.targetID == candidateTargetID
                      && dependencyExposure(
                        exposure,
                        exposesPath: candidate.path,
                        scope: candidate.scope
                      )
                      && isDependencyDeclarationVisible(
                        access: candidate.access,
                        spiGroups: candidate.spiGroups,
                        samePackage: candidateTarget.packageIdentity
                            == declarationTarget.packageIdentity,
                        exposure: exposure
                      )
              }) else {
            continue
        }
        let moduleName = candidate.moduleName ?? candidateTarget.moduleName
        result.append(
            VisibleInheritanceNominal(
                resolutionPath: "\(moduleName).\(candidate.path)",
                declaration: candidate
            )
        )
    }
    return result
}

private func visibleInheritanceAliases(
    from declaration: QualifierNominalDeclaration,
    aliases: [TargetScopedTypeAlias],
    exposures: Set<DependencyExposure>,
    manifest: WorkspaceAnalysisManifest?
) -> [VisibleInheritanceAlias] {
    var result: [VisibleInheritanceAlias] = []
    for alias in aliases {
        if targetScopeKey(alias.targetID)
            == targetScopeKey(declaration.targetID) {
            guard isSameTargetDeclarationVisible(
                access: alias.access,
                sourceIdentity: alias.sourceIdentity,
                fromSourceIdentity: declaration.sourceIdentity
            ) else {
                continue
            }
            result.append(
                VisibleInheritanceAlias(
                    record: alias.record,
                    isSameTarget: true
                )
            )
            continue
        }

        guard let manifest,
              let candidateTargetID = alias.targetID,
              let declarationTargetID = declaration.targetID,
              let candidateTarget = manifest.target(id: candidateTargetID),
              let declarationTarget = manifest.target(id: declarationTargetID),
              exposures.contains(where: { exposure in
                  exposure.targetID == candidateTargetID
                      && dependencyExposure(
                        exposure,
                        exposesPath: alias.record.path,
                        scope: alias.scope
                      )
                      && isDependencyDeclarationVisible(
                        access: alias.access,
                        spiGroups: alias.spiGroups,
                        samePackage: candidateTarget.packageIdentity
                            == declarationTarget.packageIdentity,
                        exposure: exposure
                      )
              }) else {
            continue
        }
        let moduleName = alias.moduleName ?? candidateTarget.moduleName
        let components = [moduleName] + alias.record.components
        result.append(
            VisibleInheritanceAlias(
                record: SemanticTypeAliasRecord(
                    path: components.joined(separator: "."),
                    components: components,
                    target: alias.record.target
                ),
                isSameTarget: false
            )
        )
    }
    return result
}

private func isSameTargetDeclarationVisible(
    access: QualifierDeclarationAccess,
    sourceIdentity: String,
    fromSourceIdentity: String
) -> Bool {
    switch access {
    case .private, .fileprivate:
        return sourceIdentity == fromSourceIdentity
    case .internal, .package, .public:
        return true
    }
}

private func isDependencyDeclarationVisible(
    access: QualifierDeclarationAccess,
    spiGroups: Set<String>,
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

private func dependencyExposure(
    _ exposure: DependencyExposure,
    exposesPath path: String,
    scope: QualifierShadowScope
) -> Bool {
    switch scope {
    case .file, .nominal:
        break
    case .extension, .local:
        return false
    }
    let components = path.split(separator: ".").map(String.init)
    guard let declarationPath = exposure.declarationPath else {
        return !components.isEmpty
    }
    if components == declarationPath {
        return true
    }
    guard components.count > declarationPath.count else {
        return false
    }
    return Array(components.prefix(declarationPath.count)) == declarationPath
}

private func isInheritedMember(
    _ shadow: QualifierShadowDeclaration,
    of declaration: QualifierNominalDeclaration,
    resolvedExtensionOwners: [String: String]
) -> Bool {
    switch shadow.scope {
    case .nominal(let path):
        return path == declaration.path
    case .extension(let id):
        return resolvedExtensionOwners[id] == declaration.path
    case .file, .local:
        return false
    }
}

private func isInheritedShadowVisible(
    _ shadow: QualifierShadowDeclaration,
    from site: QualifierMacroSite,
    manifest: WorkspaceAnalysisManifest?,
    siteExposures: Set<DependencyExposure>
) -> Bool {
    if targetScopeKey(shadow.targetID) == targetScopeKey(site.targetID) {
        switch shadow.access {
        case .private:
            return false
        case .fileprivate:
            return shadow.sourceIdentity == site.sourceIdentity
        case .internal, .package, .public:
            return true
        }
    }

    guard let manifest,
          let shadowTargetID = shadow.targetID,
          let siteTargetID = site.targetID,
          let shadowTarget = manifest.target(id: shadowTargetID),
          let siteTarget = manifest.target(id: siteTargetID) else {
        return false
    }
    let matchingExposures = siteExposures.filter {
        $0.targetID == shadowTargetID
    }
    guard shadow.spiGroups.isEmpty
            || matchingExposures.contains(where: {
                !shadow.spiGroups.isDisjoint(with: $0.spiGroups)
            }) else {
        return false
    }
    switch shadow.access {
    case .public:
        return true
    case .package:
        return shadowTarget.packageIdentity == siteTarget.packageIdentity
    case .internal:
        return matchingExposures.contains(where: \.isTestable)
    case .private, .fileprivate:
        return false
    }
}

private func contextIssues(
    for sites: [QualifierMacroSite]
) -> [ValidationIssue] {
    sites.compactMap { site in
        guard site.kind == .environmentBridge else { return nil }
        switch site.context {
        case .supported:
            return nil
        case .extensionContext:
            return ValidationIssue(
                code: GeneratedQualifierDiagnosticContract
                    .environmentBridgeExtensionContextUnsupportedCode,
                severity: .error,
                message: GeneratedQualifierDiagnosticContract
                    .environmentBridgeExtensionContextUnsupportedMessage,
                location: site.location,
                remediation: "Move the bridge target out of the extension lookup context and declare it at file or nominal scope.",
                metadata: ["bridgeTarget": site.declarationName]
            )
        case .local(let context):
            return ValidationIssue(
                code: GeneratedQualifierDiagnosticContract
                    .environmentBridgeLocalDeclarationUnsupportedCode,
                severity: .error,
                message: GeneratedQualifierDiagnosticContract
                    .environmentBridgeLocalDeclarationUnsupportedMessage(
                        declarationName: site.declarationName,
                        context: context
                    ),
                location: site.location,
                remediation: "Move the bridge target out of executable code and declare it at file or nominal scope.",
                metadata: [
                    "bridgeTarget": site.declarationName,
                    "localContext": context,
                ]
            )
        }
    }
}

private func targetScopeKey(_ targetID: WorkspaceTargetID?) -> String {
    targetID?.rawValue ?? "<root-path-workspace>"
}

private func sortedIssues(_ issues: [ValidationIssue]) -> [ValidationIssue] {
    issues.sorted {
        if $0.location.filePath != $1.location.filePath {
            return $0.location.filePath < $1.location.filePath
        }
        if $0.location.line != $1.location.line {
            return $0.location.line < $1.location.line
        }
        if $0.location.column != $1.location.column {
            return $0.location.column < $1.location.column
        }
        return $0.code < $1.code
    }
}

private func environmentBridgeAttribute(
    in attributes: AttributeListSyntax?
) -> AttributeSyntax? {
    findAttribute(
        named: "DIEnvironmentBridge",
        allowingQualifiedModules: ["InnoDISwiftUI"],
        in: attributes
    )
}

private func hasAttribute(
    named expectedName: String,
    in attributes: AttributeListSyntax?
) -> Bool {
    attributes?.contains { element in
        guard let attribute = element.as(AttributeSyntax.self) else {
            return false
        }
        return attribute.attributeName.trimmedDescription == expectedName
    } ?? false
}

private func spiGroups(
    in attributes: AttributeListSyntax?
) -> Set<String> {
    Set(
        attributes?.compactMap { element -> String? in
            guard let attribute = element.as(AttributeSyntax.self),
                  attribute.attributeName.trimmedDescription == "_spi",
                  let argument = attribute.arguments?
                    .as(LabeledExprListSyntax.self)?
                    .first?
                    .expression
                    .trimmedDescription,
                  !argument.isEmpty else {
                return nil
            }
            return unescapedIdentifier(argument)
        } ?? []
    )
}

private func declarationAccess(
    _ modifiers: DeclModifierListSyntax,
    defaultAccess: QualifierDeclarationAccess = .internal
) -> QualifierDeclarationAccess {
    func hasDeclarationModifier(_ name: String) -> Bool {
        modifiers.contains {
            $0.name.text == name && $0.detail == nil
        }
    }

    if hasDeclarationModifier("private") {
        return .private
    }
    if hasDeclarationModifier("fileprivate") {
        return .fileprivate
    }
    if hasDeclarationModifier("open")
        || hasDeclarationModifier("public") {
        return .public
    }
    if hasDeclarationModifier("package") {
        return .package
    }
    if hasDeclarationModifier("internal") {
        return .internal
    }
    return defaultAccess
}

private func declarationModifiers(
    _ declaration: some DeclGroupSyntax
) -> DeclModifierListSyntax {
    if let declaration = declaration.as(StructDeclSyntax.self) {
        return declaration.modifiers
    }
    if let declaration = declaration.as(ClassDeclSyntax.self) {
        return declaration.modifiers
    }
    if let declaration = declaration.as(EnumDeclSyntax.self) {
        return declaration.modifiers
    }
    if let declaration = declaration.as(ActorDeclSyntax.self) {
        return declaration.modifiers
    }
    if let declaration = declaration.as(ProtocolDeclSyntax.self) {
        return declaration.modifiers
    }
    return []
}

private func normalizedQualifierTypeReference(
    _ type: TypeSyntax
) -> SemanticTypeReference? {
    if let reference = normalizedSemanticTypeReference(type) {
        return reference
    }
    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let element = tuple.elements.first,
       element.firstName == nil,
       element.secondName == nil {
        return normalizedQualifierTypeReference(element.type)
    }
    return nil
}

private func normalizedQualifierInheritanceReference(
    _ type: TypeSyntax
) -> SemanticTypeReference? {
    if let reference = normalizedQualifierTypeReference(type) {
        return reference
    }
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return normalizedQualifierInheritanceReference(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let element = tuple.elements.first,
       element.firstName == nil,
       element.secondName == nil {
        return normalizedQualifierInheritanceReference(element.type)
    }
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return SemanticTypeReference(
            displayPath: identifier.name.text,
            components: [identifier.name.text]
        )
    }
    if let member = type.as(MemberTypeSyntax.self),
       let base = normalizedQualifierInheritanceReference(member.baseType) {
        let components = base.components + [member.name.text]
        return SemanticTypeReference(
            displayPath: components.joined(separator: "."),
            components: components
        )
    }
    return nil
}

private func identifierPatternTokens(
    in syntax: Syntax
) -> [TokenSyntax] {
    if let identifier = syntax.as(IdentifierPatternSyntax.self) {
        return [identifier.identifier]
    }
    return syntax.children(viewMode: .sourceAccurate).flatMap {
        identifierPatternTokens(in: $0)
    }
}

private func unescapedIdentifier(_ spelling: String) -> String {
    guard spelling.count >= 2,
          spelling.first == "`",
          spelling.last == "`" else {
        return spelling
    }
    return String(spelling.dropFirst().dropLast())
}
