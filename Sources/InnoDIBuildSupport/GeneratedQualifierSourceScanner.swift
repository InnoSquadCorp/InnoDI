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

struct QualifierFileScanResult {
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
                    usage: .environmentBridge(isContainer: false),
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
                    usage: .container(declaration: node),
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
                    usage: .environmentBridge(
                        isContainer: containerAttribute != nil
                    ),
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
        usage: GeneratedQualifierUsage,
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
            usage: usage,
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
