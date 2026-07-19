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
        visitNominal(node, name: node.name.text)
    }

    override func visitPost(_ node: StructDeclSyntax) {
        visitPostNominal()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        visitNominal(node, name: node.name.text)
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        visitPostNominal()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        visitNominal(node, name: node.name.text)
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        visitPostNominal()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        visitNominal(node, name: node.name.text)
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        visitPostNominal()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        visitNominal(node, name: node.name.text)
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
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

        let managedSemantics = parseManagedMemberSemantics(node.attributes)

        if let provideAttribute = managedSemantics.provideAttributes.first {
            let provideArguments = managedSemantics.provideArguments
                ?? parseProvideArguments(provideAttribute)
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

        if let subContainerAttribute = managedSemantics.subContainerAttributes.first,
           let childType = binding.type {
            let bindingParseState = extractSubContainerBindings(from: subContainerAttribute)
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
                    sameNameWiring: extractSameNameWiring(from: subContainerAttribute),
                    bindings: bindingParseState.bindings,
                    hasBindingsArgument: bindingParseState.hasArgument,
                    invalidBindingsLocation: bindingParseState.invalidLocation
                )
            )
            containerBuilders[currentContainerPath] = builder
        }

        return .skipChildren
    }

    private func visitNominal(
        _ node: some DeclGroupSyntax,
        name: String
    ) -> SyntaxVisitorContinueKind {
        declarationStack.append(name)
        let declarationPath = declarationStack.joined(separator: ".")
        nominalTypes.append(
            SemanticNominalTypeRecord(path: declarationPath, components: declarationStack)
        )

        let location = sourceLocation(for: node.positionAfterSkippingLeadingTrivia)
        if containsHierarchyAttribute("DIContainer", in: node.attributes),
           classifyDIContainerDeclaration(node).isSupported {
            containerBuilders[declarationPath] = WorkspaceHierarchyContainerBuilder(
                path: declarationPath,
                filePath: filePath,
                location: location,
                isComponent: containsHierarchyAttribute("DIComponent", in: node.attributes),
                isHierarchyRoot: containsHierarchyAttribute("DIHierarchyRoot", in: node.attributes)
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

    private func extractSameNameWiring(from attribute: AttributeSyntax) -> WorkspaceHierarchySameNameWiringRecord {
        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
            return .omitted
        }

        var sameNameWiring: WorkspaceHierarchySameNameWiringRecord = .omitted
        for argument in arguments {
            guard let labelText = argument.label?.text,
                  let label = SubContainerSameNameWiringLabel(rawValue: labelText) else {
                continue
            }

            switch label {
            case .with:
                switch parseHierarchyKeyPathDependencies(argument.expression) {
                case let .parsed(dependencies):
                    sameNameWiring = .parsed(label: label, dependencies: dependencies)
                case let .invalid(location):
                    sameNameWiring = .invalid(label: label, location: location)
                }
            }
        }

        return sameNameWiring
    }

    private func parseHierarchyKeyPathDependencies(
        _ expression: ExprSyntax
    ) -> HierarchySameNameWiringParseResult {
        guard let arrayExpr = expression.as(ArrayExprSyntax.self) else {
            return .invalid(sourceLocation(for: expression.positionAfterSkippingLeadingTrivia))
        }

        var dependencies: [HierarchyWithDependencyRecord] = []
        for element in arrayExpr.elements {
            guard let keyPath = element.expression.as(KeyPathExprSyntax.self),
                  let property = keyPath.components.last?
                    .component.as(KeyPathPropertyComponentSyntax.self)?
                    .declName.baseName.text else {
                return .invalid(sourceLocation(for: element.expression.positionAfterSkippingLeadingTrivia))
            }

            dependencies.append(
                HierarchyWithDependencyRecord(
                    name: property,
                    location: sourceLocation(for: keyPath.positionAfterSkippingLeadingTrivia)
                )
            )
        }

        return .parsed(dependencies)
    }

    private func extractSubContainerBindings(from attribute: AttributeSyntax) -> HierarchyBindingParseState {
        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
            return .omitted
        }

        for argument in arguments where argument.label?.text == "bindings" {
            guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self) else {
                return .invalid(sourceLocation(for: argument.expression.positionAfterSkippingLeadingTrivia))
            }

            var bindings: [HierarchyBindingRecord] = []
            for element in arrayExpr.elements {
                guard let tupleExpr = element.expression.as(TupleExprSyntax.self) else {
                    return .invalid(sourceLocation(for: element.expression.positionAfterSkippingLeadingTrivia))
                }

                var childName: String?
                var parentName: String?
                var childLocation: ValidationIssueLocation?
                var parentLocation: ValidationIssueLocation?

                guard tupleExpr.elements.count == 2 else {
                    return .invalid(sourceLocation(for: element.expression.positionAfterSkippingLeadingTrivia))
                }

                for tupleElement in tupleExpr.elements {
                    guard let label = tupleElement.label?.text else {
                        return .invalid(sourceLocation(for: tupleElement.expression.positionAfterSkippingLeadingTrivia))
                    }

                    switch label {
                    case "child":
                        guard childName == nil else {
                            return .invalid(sourceLocation(for: tupleElement.expression.positionAfterSkippingLeadingTrivia))
                        }
                        guard let keyPath = tupleElement.expression.as(KeyPathExprSyntax.self),
                              let property = keyPath.components.last?
                                .component.as(KeyPathPropertyComponentSyntax.self)?
                                .declName.baseName.text else {
                            return .invalid(sourceLocation(for: tupleElement.expression.positionAfterSkippingLeadingTrivia))
                        }
                        childName = property
                        childLocation = sourceLocation(for: keyPath.positionAfterSkippingLeadingTrivia)
                    case "parent":
                        guard parentName == nil else {
                            return .invalid(sourceLocation(for: tupleElement.expression.positionAfterSkippingLeadingTrivia))
                        }
                        guard let keyPath = tupleElement.expression.as(KeyPathExprSyntax.self),
                              let property = keyPath.components.last?
                                .component.as(KeyPathPropertyComponentSyntax.self)?
                                .declName.baseName.text else {
                            return .invalid(sourceLocation(for: tupleElement.expression.positionAfterSkippingLeadingTrivia))
                        }
                        parentName = property
                        parentLocation = sourceLocation(for: keyPath.positionAfterSkippingLeadingTrivia)
                    default:
                        return .invalid(sourceLocation(for: tupleElement.expression.positionAfterSkippingLeadingTrivia))
                    }
                }

                guard let childName,
                      let parentName,
                      let childLocation,
                      let parentLocation else {
                    return .invalid(sourceLocation(for: element.expression.positionAfterSkippingLeadingTrivia))
                }

                bindings.append(HierarchyBindingRecord(
                    childInputName: childName,
                    parentMemberName: parentName,
                    childLocation: childLocation,
                    parentLocation: parentLocation
                ))
            }
            return .parsed(bindings)
        }

        return .omitted
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
    let sameNameWiring: WorkspaceHierarchySameNameWiringRecord
    let bindings: [HierarchyBindingRecord]
    let hasBindingsArgument: Bool
    let invalidBindingsLocation: ValidationIssueLocation?
}

enum WorkspaceHierarchySameNameWiringRecord: Equatable {
    case omitted
    case parsed(label: SubContainerSameNameWiringLabel, dependencies: [HierarchyWithDependencyRecord])
    case invalid(label: SubContainerSameNameWiringLabel, location: ValidationIssueLocation)
}

private enum HierarchySameNameWiringParseResult {
    case parsed([HierarchyWithDependencyRecord])
    case invalid(ValidationIssueLocation)
}

private enum HierarchyBindingParseState {
    case omitted
    case parsed([HierarchyBindingRecord])
    case invalid(ValidationIssueLocation)

    var bindings: [HierarchyBindingRecord] {
        if case let .parsed(bindings) = self {
            return bindings
        }
        return []
    }

    var invalidLocation: ValidationIssueLocation? {
        if case let .invalid(location) = self {
            return location
        }
        return nil
    }

    var hasArgument: Bool {
        switch self {
        case .omitted:
            return false
        case .parsed, .invalid:
            return true
        }
    }
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
