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

        let protocolName = "\(nominalInfo.baseName)Dependencies"
        let inputMembers = hierarchyInputMembers(in: declGroup)
        let protocolDecl = makeComponentDependenciesProtocolDecl(
            accessLevel: hierarchyAccessLevelModifiers(for: declGroup.modifiers),
            protocolName: protocolName,
            inputMembers: inputMembers
        )

        return [DeclSyntax(protocolDecl)]
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
                dependencies: any \(raw: protocolName),
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
            makeComponentMountableExtensionDecl(type: type, protocolName: protocolName)
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
            makeHierarchyRootMarkerExtensionDecl(type: type)
        ]
    }
}

private struct HierarchyNominalTypeInfo {
    let baseName: String
}

private struct HierarchyInputMember {
    let name: String
    let type: TypeSyntax
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
              let attribute = findInnoDIAttribute(
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
            type: type.trimmed
        )
    }
}

private func makeComponentDependenciesProtocolDecl(
    accessLevel: DeclModifierListSyntax,
    protocolName: String,
    inputMembers: [HierarchyInputMember]
) -> ProtocolDeclSyntax {
    let requirements = inputMembers.map { member in
        MemberBlockItemSyntax(
            decl: DeclSyntax(
                VariableDeclSyntax(
                    bindingSpecifier: .keyword(.var),
                    bindings: PatternBindingListSyntax([
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier(member.name)),
                            typeAnnotation: TypeAnnotationSyntax(type: member.type),
                            accessorBlock: AccessorBlockSyntax(
                                accessors: .accessors(
                                    AccessorDeclListSyntax([
                                        AccessorDeclSyntax(accessorSpecifier: .keyword(.get))
                                    ])
                                )
                            )
                        )
                    ])
                )
            )
        )
    }

    return ProtocolDeclSyntax(
        modifiers: accessLevel,
        name: .identifier(protocolName),
        memberBlock: MemberBlockSyntax(
            members: MemberBlockItemListSyntax(requirements)
        )
    )
}

private func makeComponentMountableExtensionDecl(
    type: some TypeSyntaxProtocol,
    protocolName: String
) -> ExtensionDeclSyntax {
    ExtensionDeclSyntax(
        extendedType: TypeSyntax(type),
        inheritanceClause: InheritanceClauseSyntax(
            inheritedTypes: InheritedTypeListSyntax([
                InheritedTypeSyntax(
                    type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("_InnoDIComponentMountable")))
                )
            ])
        ),
        memberBlock: MemberBlockSyntax(
            members: MemberBlockItemListSyntax([
                MemberBlockItemSyntax(
                    decl: DeclSyntax(
                        TypeAliasDeclSyntax(
                            typealiasKeyword: .keyword(.typealias, trailingTrivia: .space),
                            name: .identifier("_InnoDIComponentDependencies"),
                            initializer: TypeInitializerClauseSyntax(
                                equal: .equalToken(leadingTrivia: .space, trailingTrivia: .space),
                                value: TypeSyntax(
                                    SomeOrAnyTypeSyntax(
                                        someOrAnySpecifier: .keyword(.any, trailingTrivia: .space),
                                        constraint: TypeSyntax(
                                            IdentifierTypeSyntax(name: .identifier(protocolName))
                                        )
                                    )
                                )
                            )
                        )
                    )
                ),
                MemberBlockItemSyntax(
                    decl: DeclSyntax(
                        TypeAliasDeclSyntax(
                            typealiasKeyword: .keyword(.typealias, trailingTrivia: .space),
                            name: .identifier("_InnoDIComponentOverrides"),
                            initializer: TypeInitializerClauseSyntax(
                                equal: .equalToken(leadingTrivia: .space, trailingTrivia: .space),
                                value: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Overrides")))
                            )
                        )
                    )
                ),
            ])
        )
    )
}

private func makeHierarchyRootMarkerExtensionDecl(
    type: some TypeSyntaxProtocol
) -> ExtensionDeclSyntax {
    ExtensionDeclSyntax(
        extendedType: TypeSyntax(type),
        inheritanceClause: InheritanceClauseSyntax(
            inheritedTypes: InheritedTypeListSyntax([
                InheritedTypeSyntax(
                    type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("DIHierarchyRootMarker")))
                )
            ])
        ),
        memberBlock: MemberBlockSyntax(members: MemberBlockItemListSyntax([]))
    )
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

private func hierarchyAccessLevelModifiers(for modifiers: DeclModifierListSyntax?) -> DeclModifierListSyntax {
    let accessLevel = hierarchyAccessLevelModifierText(for: modifiers).trimmingCharacters(in: .whitespaces)
    guard !accessLevel.isEmpty else {
        return DeclModifierListSyntax([])
    }

    let keyword: TokenSyntax
    switch accessLevel {
    case "public":
        keyword = .keyword(.public)
    case "package":
        keyword = .keyword(.package)
    case "internal":
        keyword = .keyword(.internal)
    case "fileprivate":
        keyword = .keyword(.fileprivate)
    case "private":
        keyword = .keyword(.private)
    default:
        return DeclModifierListSyntax([])
    }

    return DeclModifierListSyntax([
        DeclModifierSyntax(name: keyword)
    ])
}

private func hasHierarchyAttribute(named name: String, in attributes: AttributeListSyntax?) -> Bool {
    findInnoDIAttribute(named: name, in: attributes) != nil
}
