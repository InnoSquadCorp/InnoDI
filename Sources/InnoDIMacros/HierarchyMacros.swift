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
            context.emit(
                SimpleDiagnostic.componentRequiresContainer(),
                at: Syntax(node)
            )
            return []
        }

        guard let targetName = hierarchyNominalNameToken(for: declGroup) else {
            return []
        }
        guard !isEscapedInnoDIIdentifier(targetName) else {
            context.emit(
                SimpleDiagnostic.componentEscapedTargetUnsupported(
                    name: unescapedInnoDIIdentifierName(targetName)
                ),
                at: Syntax(targetName)
            )
            return []
        }

        guard classifyDIContainerDeclaration(
            declGroup,
            lexicalContext: context.lexicalContext
        ).isSupported else {
            return []
        }
        guard !containerHasReservedGeneratedName(
            in: declGroup,
            lexicalContext: context.lexicalContext
        ) else {
            return []
        }
        guard let model = validatedDIComponentContainerModel(
            declaration: declGroup,
            context: context
        ) else {
            return []
        }

        guard let nominalInfo = hierarchyNominalTypeInfo(for: declGroup) else {
            return []
        }

        let protocolName = "\(nominalInfo.baseName)Dependencies"
        let inputMembers = hierarchyInputMembers(in: model)
        let protocolDecl = makeComponentDependenciesProtocolDecl(
            accessLevel: hierarchyAccessLevelModifiers(for: declGroup.modifiers),
            protocolName: protocolName,
            inputMembers: inputMembers,
            isMainActor: model.options.mainActor
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
        guard let targetName = hierarchyNominalNameToken(for: declaration),
              !isEscapedInnoDIIdentifier(targetName) else {
            return []
        }

        guard classifyDIContainerDeclaration(
            declaration,
            lexicalContext: context.lexicalContext
        ).isSupported else {
            return []
        }
        guard !containerHasReservedGeneratedName(
            in: declaration,
            lexicalContext: context.lexicalContext
        ) else {
            return []
        }

        if DIContainerParser.findOverridesNameConflict(in: declaration) != nil {
            context.emit(
                SimpleDiagnostic.componentOverridesBuilderRequired(),
                at: Syntax(node)
            )
            return []
        }
        guard let model = validatedDIComponentContainerModel(
            declaration: declaration,
            context: context
        ) else {
            return []
        }

        guard let nominalInfo = hierarchyNominalTypeInfo(for: declaration) else {
            return []
        }

        let accessLevel = hierarchyAccessLevelModifierText(for: declaration.modifiers)
        let protocolName = "\(nominalInfo.baseName)Dependencies"
        let inputMembers = hierarchyInputMembers(in: model)
        let callArguments = inputMembers.map {
            "\($0.name): _innoDIDependencies.\($0.name)"
        } + ["_innoDIApplyOverrides"]
        let joinedArguments = callArguments.joined(separator: ", ")
        let isMainActor = model.options.mainActor
        let applyOverridesType = overrideApplyClosureType(
            isMainActor: isMainActor
        ).trimmedDescription

        var initDecl: DeclSyntax = """
            \(raw: accessLevel)init(
                dependencies _innoDIDependencies: any \(raw: protocolName),
                _ _innoDIApplyOverrides: \(raw: applyOverridesType) = { _ in }
            ) {
                self.init(\(raw: joinedArguments))
            }
            """

        if isMainActor, let initializer = initDecl.as(InitializerDeclSyntax.self) {
            initDecl = DeclSyntax(
                initializer.with(\.attributes, mainActorAttributeList())
            )
        }

        return [initDecl.prependingMARK("// MARK: - Initialization")]
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
        guard let targetName = hierarchyNominalNameToken(for: declaration),
              !isEscapedInnoDIIdentifier(targetName) else {
            return []
        }

        guard classifyDIContainerDeclaration(
            declaration,
            lexicalContext: context.lexicalContext
        ).isSupported else {
            return []
        }
        guard !containerHasReservedGeneratedName(
            in: declaration,
            lexicalContext: context.lexicalContext
        ) else {
            return []
        }

        if DIContainerParser.findOverridesNameConflict(in: declaration) != nil {
            return []
        }
        guard let model = validatedDIComponentContainerModel(
            declaration: declaration,
            context: context
        ) else {
            return []
        }

        guard let nominalInfo = hierarchyNominalTypeInfo(for: declaration) else {
            return []
        }

        let protocolName = "\(nominalInfo.baseName)Dependencies"
        let accessLevel = hierarchyAccessLevelModifiers(for: declaration.modifiers)
        let dependenciesType = qualifiedComponentDependenciesType(
            for: type,
            protocolName: protocolName
        )

        return [
            makeComponentMountableExtensionDecl(
                type: type,
                dependenciesType: dependenciesType,
                accessLevel: accessLevel,
                isMainActor: model.options.mainActor
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
            context.emit(
                SimpleDiagnostic.hierarchyRootRequiresContainer(),
                at: Syntax(node)
            )
            return []
        }

        guard classifyDIContainerDeclaration(
            declaration,
            lexicalContext: context.lexicalContext
        ).isSupported else {
            return []
        }
        guard !containerHasReservedGeneratedName(
            in: declaration,
            lexicalContext: context.lexicalContext
        ) else {
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

private func hierarchyNominalNameToken(
    for declaration: some DeclGroupSyntax
) -> TokenSyntax? {
    if let structDecl = declaration.as(StructDeclSyntax.self) {
        return structDecl.name
    }
    if let classDecl = declaration.as(ClassDeclSyntax.self) {
        return classDecl.name
    }
    if let actorDecl = declaration.as(ActorDeclSyntax.self) {
        return actorDecl.name
    }
    if let enumDecl = declaration.as(EnumDeclSyntax.self) {
        return enumDecl.name
    }
    return nil
}

private func hierarchyNominalTypeInfo(for declaration: some DeclGroupSyntax) -> HierarchyNominalTypeInfo? {
    if let name = hierarchyNominalNameToken(for: declaration) {
        return HierarchyNominalTypeInfo(baseName: name.text)
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

private func hierarchyInputMembers(
    in model: DIContainerExpansionModel
) -> [HierarchyInputMember] {
    model.inputMembers.map { member in
        return HierarchyInputMember(
            name: member.name,
            type: member.type.trimmed
        )
    }
}

/// Every `@DIComponent` role must agree with the container member role about
/// whether public support can be generated. Run the complete parse,
/// validation, and codegen gate without re-emitting diagnostics; otherwise a
/// rejected container can leave a peer protocol, initializer, or conformance
/// that references support `@DIContainer` deliberately suppressed.
private func validatedDIComponentContainerModel(
    declaration: some DeclGroupSyntax,
    context: some MacroExpansionContext
) -> DIContainerExpansionModel? {
    guard DIContainerParser.userDefinedInitializers(
        in: declaration
    ).isEmpty,
    DIContainerParser.findOverridesNameConflict(in: declaration) == nil else {
        return nil
    }

    let validationContext = DiagnosticSuppressingMacroExpansionContext(
        forwardingTo: context
    )
    guard let model = DIContainerParser.parse(
        declaration: declaration,
        context: validationContext
    ), DIContainerValidator.validate(
        model: model,
        declaration: declaration,
        context: validationContext
    ) else {
        return nil
    }

    do {
        _ = try DIContainerCodeGenerator.generateAll(for: model)
        return model
    } catch {
        return nil
    }
}

private func makeComponentDependenciesProtocolDecl(
    accessLevel: DeclModifierListSyntax,
    protocolName: String,
    inputMembers: [HierarchyInputMember],
    isMainActor: Bool
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
        attributes: isMainActor ? mainActorAttributeList() : AttributeListSyntax([]),
        modifiers: accessLevel,
        name: .identifier(protocolName),
        memberBlock: MemberBlockSyntax(
            members: MemberBlockItemListSyntax(requirements)
        )
    )
}

private func makeComponentMountableExtensionDecl(
    type: some TypeSyntaxProtocol,
    dependenciesType: TypeSyntax,
    accessLevel: DeclModifierListSyntax,
    isMainActor: Bool
) -> ExtensionDeclSyntax {
    ExtensionDeclSyntax(
        extendedType: TypeSyntax(type),
        inheritanceClause: InheritanceClauseSyntax(
            inheritedTypes: InheritedTypeListSyntax([
                InheritedTypeSyntax(
                    type: TypeSyntax(
                        MemberTypeSyntax(
                            baseType: IdentifierTypeSyntax(
                                name: .identifier("InnoDI")
                            ),
                            name: .identifier(
                                isMainActor
                                    ? "_InnoDIMainActorComponentMountable"
                                    : "_InnoDIComponentMountable"
                            )
                        )
                    )
                )
            ])
        ),
        memberBlock: MemberBlockSyntax(
            members: MemberBlockItemListSyntax([
                MemberBlockItemSyntax(
                    decl: DeclSyntax(
                        TypeAliasDeclSyntax(
                            modifiers: accessLevel,
                            typealiasKeyword: .keyword(.typealias, trailingTrivia: .space),
                            name: .identifier("_InnoDIComponentDependencies"),
                            initializer: TypeInitializerClauseSyntax(
                                equal: .equalToken(leadingTrivia: .space, trailingTrivia: .space),
                                value: TypeSyntax(
                                    SomeOrAnyTypeSyntax(
                                        someOrAnySpecifier: .keyword(.any, trailingTrivia: .space),
                                        constraint: dependenciesType
                                    )
                                )
                            )
                        )
                    )
                ),
                MemberBlockItemSyntax(
                    decl: DeclSyntax(
                        TypeAliasDeclSyntax(
                            modifiers: accessLevel,
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

/// A component dependency protocol is emitted as a peer of the container. For
/// a nested container that makes it a sibling in the enclosing nominal, while
/// the mountable conformance is emitted in a file-scope extension. Preserve the
/// enclosing path from the compiler-provided type so that extension can resolve
/// the peer protocol from any supported nesting depth.
private func qualifiedComponentDependenciesType(
    for type: some TypeSyntaxProtocol,
    protocolName: String
) -> TypeSyntax {
    guard var memberType = TypeSyntax(type).as(MemberTypeSyntax.self) else {
        return TypeSyntax(IdentifierTypeSyntax(name: .identifier(protocolName)))
    }

    memberType = memberType.with(\.name, .identifier(protocolName))
    memberType = memberType.with(\.genericArgumentClause, nil)
    return TypeSyntax(memberType)
}

private func makeHierarchyRootMarkerExtensionDecl(
    type: some TypeSyntaxProtocol
) -> ExtensionDeclSyntax {
    ExtensionDeclSyntax(
        extendedType: TypeSyntax(type),
        inheritanceClause: InheritanceClauseSyntax(
            inheritedTypes: InheritedTypeListSyntax([
                InheritedTypeSyntax(
                    type: TypeSyntax(
                        MemberTypeSyntax(
                            baseType: IdentifierTypeSyntax(
                                name: .identifier("InnoDI")
                            ),
                            name: .identifier("DIHierarchyRootMarker")
                        )
                    )
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

internal func hasHierarchyAttribute(named name: String, in attributes: AttributeListSyntax?) -> Bool {
    findInnoDIAttribute(named: name, in: attributes) != nil
}
