import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct DIComponentMacro {}

extension DIComponentMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let declGroup = hierarchyDeclGroup(from: declaration) else {
            return []
        }

        guard hasHierarchyAttribute(named: "DIContainer", in: declGroup.attributes) else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: SimpleDiagnostic.componentRequiresContainer()
                )
            )
            return []
        }

        guard let nominalInfo = hierarchyNominalTypeInfo(for: declGroup) else {
            return []
        }

        let accessLevel = hierarchyAccessLevelModifierText(for: declGroup.modifiers)
        let protocolName = "\(nominalInfo.baseName)Dependencies"
        let inputMembers = hierarchyInputMembers(in: declGroup)
        let requirements = inputMembers.map { member in
            "var \(member.name): \(member.typeSource) { get }"
        }
        .joined(separator: "\n")

        let protocolBody = requirements.isEmpty ? "" : "\n\(requirements)\n"
        let protocolDecl: DeclSyntax = """
            \(raw: accessLevel)protocol \(raw: protocolName) {\(raw: protocolBody)}
            """

        return [protocolDecl]
    }
}

extension DIComponentMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try expansion(of: node, providingMembersOf: declaration, in: context)
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard hasHierarchyAttribute(named: "DIContainer", in: declaration.attributes) else {
            return []
        }

        if DIContainerParser.findOverridesNameConflict(in: declaration) != nil {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: SimpleDiagnostic.componentOverridesBuilderRequired()
                )
            )
            return []
        }

        guard let nominalInfo = hierarchyNominalTypeInfo(for: declaration) else {
            return []
        }

        let accessLevel = hierarchyAccessLevelModifierText(for: declaration.modifiers)
        let protocolName = "\(nominalInfo.baseName)Dependencies"
        let inputMembers = hierarchyInputMembers(in: declaration)
        let callArguments = inputMembers.map {
            "\($0.name): dependencies.\($0.name)"
        } + ["applyOverrides"]
        let joinedArguments = callArguments.joined(separator: ", ")

        let initDecl: DeclSyntax = """
            \(raw: accessLevel)init(
                dependencies: some \(raw: protocolName),
                _ applyOverrides: (inout Overrides) -> Void = { _ in }
            ) {
                self.init(\(raw: joinedArguments))
            }
            """

        return [initDecl]
    }
}

extension DIComponentMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard hasHierarchyAttribute(named: "DIContainer", in: declaration.attributes) else {
            return []
        }

        if DIContainerParser.findOverridesNameConflict(in: declaration) != nil {
            return []
        }

        guard let nominalInfo = hierarchyNominalTypeInfo(for: declaration) else {
            return []
        }

        let protocolName = "\(nominalInfo.baseName)Dependencies"

        return [
            try ExtensionDeclSyntax(
                """
                extension \(type): _InnoDIComponentMountable {
                    typealias _InnoDIComponentDependencies = any \(raw: protocolName)
                    typealias _InnoDIComponentOverrides = Overrides
                }
                """
            )
        ]
    }
}

public struct DIHierarchyRootMacro {}

extension DIHierarchyRootMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard hasHierarchyAttribute(named: "DIContainer", in: declaration.attributes) else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: SimpleDiagnostic.hierarchyRootRequiresContainer()
                )
            )
            return []
        }

        return [
            try ExtensionDeclSyntax("extension \(type): DIHierarchyRootMarker {}")
        ]
    }
}

private struct HierarchyNominalTypeInfo {
    let baseName: String
}

private struct HierarchyInputMember {
    let name: String
    let typeSource: String
}

private func hierarchyNominalTypeInfo(for declaration: some DeclGroupSyntax) -> HierarchyNominalTypeInfo? {
    if let structDecl = declaration.as(StructDeclSyntax.self) {
        return HierarchyNominalTypeInfo(baseName: structDecl.name.text)
    }
    if let classDecl = declaration.as(ClassDeclSyntax.self) {
        return HierarchyNominalTypeInfo(baseName: classDecl.name.text)
    }
    if let actorDecl = declaration.as(ActorDeclSyntax.self) {
        return HierarchyNominalTypeInfo(baseName: actorDecl.name.text)
    }
    if let enumDecl = declaration.as(EnumDeclSyntax.self) {
        return HierarchyNominalTypeInfo(baseName: enumDecl.name.text)
    }
    return nil
}

private func hierarchyDeclGroup(from declaration: some DeclSyntaxProtocol) -> (any DeclGroupSyntax)? {
    if let structDecl = declaration.as(StructDeclSyntax.self) {
        return structDecl
    }
    if let classDecl = declaration.as(ClassDeclSyntax.self) {
        return classDecl
    }
    if let actorDecl = declaration.as(ActorDeclSyntax.self) {
        return actorDecl
    }
    if let enumDecl = declaration.as(EnumDeclSyntax.self) {
        return enumDecl
    }
    return nil
}

private func hierarchyInputMembers(in declaration: some DeclGroupSyntax) -> [HierarchyInputMember] {
    declaration.memberBlock.members.compactMap { member in
        guard let variableDecl = member.decl.as(VariableDeclSyntax.self),
              !variableDecl.modifiers.contains(where: { $0.name.text == "static" }),
              let attribute = findAttribute(
                named: "Provide",
                in: variableDecl.attributes
              ),
              let binding = variableDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let type = binding.typeAnnotation?.type,
              parseProvideArguments(attribute).scope == .input else {
            return nil
        }

        return HierarchyInputMember(
            name: identifier.identifier.text,
            typeSource: type.trimmedDescription
        )
    }
}

private func hierarchyAccessLevelModifierText(for modifiers: DeclModifierListSyntax?) -> String {
    guard let modifiers else {
        return ""
    }

    for modifier in modifiers {
        switch modifier.name.tokenKind {
        case .keyword(.public):
            return "public "
        case .keyword(.package):
            return "package "
        case .keyword(.internal):
            return "internal "
        case .keyword(.fileprivate):
            return "fileprivate "
        case .keyword(.private):
            return "private "
        default:
            continue
        }
    }

    return ""
}

private func hasHierarchyAttribute(named name: String, in attributes: AttributeListSyntax?) -> Bool {
    attributes?.contains(where: { element in
        guard let attribute = element.as(AttributeSyntax.self) else {
            return false
        }
        return attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == name
    }) == true
}
