import Foundation
import InnoDICore
import SwiftSyntax

struct WorkspaceHierarchyMemberRecord: Equatable {
    let rawTypeSpelling: String
    let semanticTypeReference: SemanticTypeReference?
}

func makeHierarchyMemberRecord(from type: TypeSyntax?) -> WorkspaceHierarchyMemberRecord {
    WorkspaceHierarchyMemberRecord(
        rawTypeSpelling: type?.trimmedDescription ?? "<unknown>",
        semanticTypeReference: type.flatMap(normalizedSemanticTypeReference)
    )
}

final class WorkspaceHierarchyFileCollector: SyntaxVisitor {
    private let filePath: String
    private let locationConverter: SourceLocationConverter
    private var declarationStack: [String] = []
    private var containerContextStack: [String?] = []
    private var containerBuilders: [String: WorkspaceHierarchyContainerBuilder] = [:]

    private(set) var nominalTypes: [SemanticNominalTypeRecord] = []
    private(set) var typeAliases: [SemanticTypeAliasRecord] = []

    var containers: [WorkspaceHierarchyContainerRecord] {
        containerBuilders.values
            .map { builder in
                WorkspaceHierarchyContainerRecord(
                    containerID: "",
                    nominalPath: builder.path,
                    moduleID: "",
                    displayName: builder.path.split(separator: ".").last.map(String.init) ?? builder.path,
                    filePath: builder.filePath,
                    location: builder.location,
                    isComponent: builder.isComponent,
                    isHierarchyRoot: builder.isHierarchyRoot,
                    inputMembers: builder.inputMembers,
                    providedMembers: builder.providedMembers,
                    subContainers: builder.subContainers
                )
            }
            .sorted { $0.nominalPath < $1.nominalPath }
    }

    init(filePath: String, syntax: SourceFileSyntax) {
        self.filePath = filePath
        self.locationConverter = SourceLocationConverter(fileName: filePath, tree: syntax)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        visitNominal(node: Syntax(node), name: node.name.text, attributes: node.attributes)
    }

    override func visitPost(_ node: StructDeclSyntax) {
        visitPostNominal()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        visitNominal(node: Syntax(node), name: node.name.text, attributes: node.attributes)
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        visitPostNominal()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        visitNominal(node: Syntax(node), name: node.name.text, attributes: node.attributes)
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        visitPostNominal()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        visitNominal(node: Syntax(node), name: node.name.text, attributes: node.attributes)
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        visitPostNominal()
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let components = declarationStack + [node.name.text]
        let path = components.joined(separator: ".")

        if let targetReference = normalizedSemanticTypeReference(node.initializer.value) {
            typeAliases.append(
                SemanticTypeAliasRecord(
                    path: path,
                    components: components,
                    target: targetReference
                )
            )
        }

        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let currentContainerPath = containerContextStack.last ?? nil,
              node.parent?.is(MemberBlockItemSyntax.self) == true,
              let binding = hierarchyValidatedBinding(node) else {
            return .skipChildren
        }

        if let provideAttribute = findInnoDIAttribute(named: "Provide", in: node.attributes) {
            let provideArguments = parseProvideArguments(provideAttribute)
            containerBuilders[currentContainerPath, default: WorkspaceHierarchyContainerBuilder(
                path: currentContainerPath,
                filePath: filePath,
                location: sourceLocation(for: node.positionAfterSkippingLeadingTrivia)
            )]
            .providedMembers[binding.name] = makeHierarchyMemberRecord(from: binding.type)

            if provideArguments.scope == .input {
                containerBuilders[currentContainerPath]?.inputMembers[binding.name] = makeHierarchyMemberRecord(from: binding.type)
            }
        }

        if let subContainerAttribute = findInnoDIAttribute(named: "SubContainer", in: node.attributes),
           let childType = binding.type {
            var builder = containerBuilders[currentContainerPath, default: WorkspaceHierarchyContainerBuilder(
                path: currentContainerPath,
                filePath: filePath,
                location: sourceLocation(for: node.positionAfterSkippingLeadingTrivia)
            )]
            builder.subContainers.append(
                WorkspaceHierarchySubContainerRecord(
                    memberName: binding.name,
                    location: sourceLocation(for: subContainerAttribute.positionAfterSkippingLeadingTrivia),
                    childReferenceDisplayPath: childType.trimmedDescription,
                    childReference: normalizedSemanticTypeReference(childType),
                    hasExplicitSameNameWiring: hasExplicitSameNameWiring(in: subContainerAttribute),
                    withDependencies: extractWithDependencies(from: subContainerAttribute),
                    bindings: extractSubContainerBindings(from: subContainerAttribute)
                )
            )
            containerBuilders[currentContainerPath] = builder
        }

        return .skipChildren
    }

    private func visitNominal(
        node: Syntax,
        name: String,
        attributes: AttributeListSyntax?
    ) -> SyntaxVisitorContinueKind {
        declarationStack.append(name)
        let declarationPath = declarationStack.joined(separator: ".")
        nominalTypes.append(
            SemanticNominalTypeRecord(path: declarationPath, components: declarationStack)
        )

        let location = sourceLocation(for: node.positionAfterSkippingLeadingTrivia)
        if containsHierarchyAttribute("DIContainer", in: attributes) {
            containerBuilders[declarationPath] = WorkspaceHierarchyContainerBuilder(
                path: declarationPath,
                filePath: filePath,
                location: location,
                isComponent: containsHierarchyAttribute("DIComponent", in: attributes),
                isHierarchyRoot: containsHierarchyAttribute("DIHierarchyRoot", in: attributes)
            )
            containerContextStack.append(declarationPath)
        } else {
            containerContextStack.append(nil)
        }

        return .visitChildren
    }

    private func visitPostNominal() {
        if !declarationStack.isEmpty {
            declarationStack.removeLast()
        }
        if !containerContextStack.isEmpty {
            containerContextStack.removeLast()
        }
    }

    private func sourceLocation(for position: AbsolutePosition) -> ValidationIssueLocation {
        let location = locationConverter.location(for: position)
        return ValidationIssueLocation(
            filePath: filePath,
            line: location.line,
            column: location.column
        )
    }

    private func extractWithDependencies(from attribute: AttributeSyntax) -> [HierarchyWithDependencyRecord] {
        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
            return []
        }

        var dependencies: [HierarchyWithDependencyRecord] = []
        for argument in arguments {
            guard let label = argument.label?.text else { continue }
            switch label {
            case "with":
                guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self) else {
                    continue
                }

                dependencies += arrayExpr.elements.compactMap { element in
                    guard let keyPath = element.expression.as(KeyPathExprSyntax.self),
                          let property = keyPath.components.last?
                            .component.as(KeyPathPropertyComponentSyntax.self)?
                            .declName.baseName.text else {
                        return nil
                    }

                    return HierarchyWithDependencyRecord(
                        name: property,
                        location: sourceLocation(for: keyPath.positionAfterSkippingLeadingTrivia)
                    )
                }
            case "withNames":
                guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self) else {
                    continue
                }

                dependencies += arrayExpr.elements.compactMap { element in
                    guard let literal = element.expression.as(StringLiteralExprSyntax.self),
                          literal.segments.count == 1,
                          case let .stringSegment(segment)? = literal.segments.first else {
                        return nil
                    }

                    return HierarchyWithDependencyRecord(
                        name: segment.content.text,
                        location: sourceLocation(for: literal.positionAfterSkippingLeadingTrivia)
                    )
                }
            default:
                continue
            }
        }

        return dependencies
    }

    private func hasExplicitSameNameWiring(in attribute: AttributeSyntax) -> Bool {
        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
            return false
        }

        return arguments.contains { argument in
            guard let label = argument.label?.text else {
                return false
            }
            return label == "with" || label == "withNames"
        }
    }

    private func extractSubContainerBindings(from attribute: AttributeSyntax) -> [HierarchyBindingRecord] {
        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
            return []
        }

        for argument in arguments where argument.label?.text == "bindings" {
            guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self) else {
                return []
            }

            return arrayExpr.elements.compactMap { element in
                guard let tupleExpr = element.expression.as(TupleExprSyntax.self) else {
                    return nil
                }

                var childName: String?
                var parentName: String?
                var childLocation: ValidationIssueLocation?
                var parentLocation: ValidationIssueLocation?

                for tupleElement in tupleExpr.elements {
                    guard let label = tupleElement.label?.text,
                          let keyPath = tupleElement.expression.as(KeyPathExprSyntax.self),
                          let property = keyPath.components.last?
                            .component.as(KeyPathPropertyComponentSyntax.self)?
                            .declName.baseName.text else {
                        continue
                    }

                    let location = sourceLocation(for: keyPath.positionAfterSkippingLeadingTrivia)
                    switch label {
                    case "child":
                        childName = property
                        childLocation = location
                    case "parent":
                        parentName = property
                        parentLocation = location
                    default:
                        continue
                    }
                }

                guard let childName,
                      let parentName,
                      let childLocation,
                      let parentLocation else {
                    return nil
                }

                return HierarchyBindingRecord(
                    childInputName: childName,
                    parentMemberName: parentName,
                    childLocation: childLocation,
                    parentLocation: parentLocation
                )
            }
        }

        return []
    }
}

struct WorkspaceHierarchyContainerRecord: Equatable {
    let containerID: String
    let nominalPath: String
    let moduleID: String
    let displayName: String
    let filePath: String
    let location: ValidationIssueLocation
    let isComponent: Bool
    let isHierarchyRoot: Bool
    let inputMembers: [String: WorkspaceHierarchyMemberRecord]
    let providedMembers: [String: WorkspaceHierarchyMemberRecord]
    let subContainers: [WorkspaceHierarchySubContainerRecord]

    var path: String { nominalPath }

    func resolved(moduleID: String) -> WorkspaceHierarchyContainerRecord {
        WorkspaceHierarchyContainerRecord(
            containerID: workspaceContainerID(moduleID: moduleID, nominalPath: nominalPath, filePath: filePath),
            nominalPath: nominalPath,
            moduleID: moduleID,
            displayName: displayName,
            filePath: filePath,
            location: location,
            isComponent: isComponent,
            isHierarchyRoot: isHierarchyRoot,
            inputMembers: inputMembers,
            providedMembers: providedMembers,
            subContainers: subContainers
        )
    }
}

private struct WorkspaceHierarchyContainerBuilder {
    let path: String
    let filePath: String
    let location: ValidationIssueLocation
    var isComponent: Bool = false
    var isHierarchyRoot: Bool = false
    var inputMembers: [String: WorkspaceHierarchyMemberRecord] = [:]
    var providedMembers: [String: WorkspaceHierarchyMemberRecord] = [:]
    var subContainers: [WorkspaceHierarchySubContainerRecord] = []
}

struct WorkspaceHierarchySubContainerRecord: Equatable {
    let memberName: String
    let location: ValidationIssueLocation
    let childReferenceDisplayPath: String
    let childReference: SemanticTypeReference?
    let hasExplicitSameNameWiring: Bool
    let withDependencies: [HierarchyWithDependencyRecord]
    let bindings: [HierarchyBindingRecord]
}

struct HierarchyWithDependencyRecord: Equatable {
    let name: String
    let location: ValidationIssueLocation
}

struct HierarchyBindingRecord: Equatable {
    let childInputName: String
    let parentMemberName: String
    let childLocation: ValidationIssueLocation
    let parentLocation: ValidationIssueLocation
}

private struct HierarchyValidatedBinding {
    let name: String
    let type: TypeSyntax?
}

private func hierarchyValidatedBinding(_ varDecl: VariableDeclSyntax) -> HierarchyValidatedBinding? {
    guard varDecl.bindings.count == 1,
          let binding = varDecl.bindings.first,
          let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
        return nil
    }

    return HierarchyValidatedBinding(
        name: identifier.identifier.text,
        type: binding.typeAnnotation?.type
    )
}

private func containsHierarchyAttribute(_ name: String, in attributes: AttributeListSyntax?) -> Bool {
    findInnoDIAttribute(named: name, in: attributes) != nil
}

func workspaceContainerID(moduleID: String, nominalPath: String, filePath: String) -> String {
    "\(moduleID)|\(nominalPath)|\(NSString(string: filePath).standardizingPath)"
}

func unknownWorkspaceModuleID(forFilePath filePath: String) -> String {
    "unknown|\(NSString(string: filePath).standardizingPath)"
}
