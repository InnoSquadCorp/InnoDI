import Foundation
import InnoDICore
import InnoDIWorkspaceAnalysis
import SwiftSyntax

/// Build-stage semantic validator for module-wide container relationships.
///
/// This pass runs after cross-file custom-init validation and before DAG
/// validation. It collects lightweight syntax records for container
/// declarations, sub-container bindings, and deferred-wrapper spellings, then
/// resolves them through `SemanticResolverIndex` so the coordinator can emit
/// structured diagnostics without invoking the Swift type checker.
package enum ContainerSemanticBuildValidator {
    package static func validate(rootPath: String) throws -> ValidationIssueReport {
        try validate(snapshot: loadWorkspaceSourceSnapshot(rootPath: rootPath))
    }

    package static func validateDeclarationMatrix(
        rootPath: String
    ) throws -> ValidationIssueReport {
        validateDeclarationMatrix(
            snapshot: try loadWorkspaceSourceSnapshot(rootPath: rootPath)
        )
    }

    package static func validateDeclarationMatrix(
        snapshot: WorkspaceSourceSnapshot
    ) -> ValidationIssueReport {
        var issues: [ValidationIssue] = []

        for sourceFile in snapshot.files {
            let collector = DIContainerDeclarationSupportCollector()
            collector.walk(sourceFile.syntax)
            let converter = SourceLocationConverter(
                fileName: sourceFile.filePath,
                tree: sourceFile.syntax
            )

            for declarationIssue in collector.issues {
                guard let code = declarationIssue.support.diagnosticCode,
                      let message = declarationIssue.support.diagnosticMessage else {
                    continue
                }
                let sourceLocation = converter.location(
                    for: declarationIssue.attributePosition
                )
                issues.append(
                    ValidationIssue(
                        code: code,
                        severity: .error,
                        message: message,
                        location: ValidationIssueLocation(
                            filePath: sourceFile.filePath,
                            line: sourceLocation.line,
                            column: sourceLocation.column
                        ),
                        remediation: declarationIssue.support.remediation
                    )
                )
            }
        }

        issues.sort {
            if $0.location.filePath != $1.location.filePath {
                return $0.location.filePath < $1.location.filePath
            }
            if $0.location.line != $1.location.line {
                return $0.location.line < $1.location.line
            }
            return $0.location.column < $1.location.column
        }
        return ValidationIssueReport(issues: issues)
    }

    package static func validate(snapshot: WorkspaceSourceSnapshot) throws -> ValidationIssueReport {
        let declarationMatrix = validateDeclarationMatrix(snapshot: snapshot)
        if declarationMatrix.hasFailures {
            return declarationMatrix
        }

        var collectorResults: [ContainerSemanticFileCollector] = []
        for sourceFile in snapshot.files {
            let collector = ContainerSemanticFileCollector(
                filePath: sourceFile.filePath,
                syntax: sourceFile.syntax
            )
            collector.walk(sourceFile.syntax)
            collectorResults.append(collector)
        }

        let nominalTypes = collectorResults.flatMap(\.nominalTypes)
        let typeAliases = collectorResults.flatMap(\.typeAliases)
        let containers = collectorResults.flatMap(\.containers)
        let subContainers = collectorResults.flatMap(\.subContainers)
        let wrapperParameters = collectorResults.flatMap(\.wrapperParameters)
        let wrapperDeclarations = collectorResults.flatMap(\.wrapperDeclarations)
        let wrapperAliases = collectorResults.flatMap(\.wrapperAliases)

        let semanticResolver = SemanticResolverIndex(
            nominalTypes: nominalTypes,
            topLevelTypeAliases: typeAliases
        )
        let containerInputsByPath = Dictionary(uniqueKeysWithValues: containers.map { ($0.path, $0) })
        let containerCandidatePaths = Set(containerInputsByPath.keys)
        let wrapperDeclarationsByPath = Dictionary(uniqueKeysWithValues: wrapperDeclarations.map { ($0.path, $0) })
        let wrapperAliasesByPath = Dictionary(uniqueKeysWithValues: wrapperAliases.map { ($0.path, $0) })

        var issues = validateSubContainerBindings(
            subContainers,
            semanticResolver: semanticResolver,
            containerInputsByPath: containerInputsByPath,
            containerCandidatePaths: containerCandidatePaths
        )
        issues.append(contentsOf: validateDeferredWrapperParameters(
            wrapperParameters,
            wrapperDeclarationsByPath: wrapperDeclarationsByPath,
            wrapperAliasesByPath: wrapperAliasesByPath
        ))

        issues.sort {
            if $0.location.filePath != $1.location.filePath { return $0.location.filePath < $1.location.filePath }
            if $0.location.line != $1.location.line { return $0.location.line < $1.location.line }
            return $0.location.column < $1.location.column
        }

        return ValidationIssueReport(issues: issues)
    }
}

struct SemanticContainerRecord: Equatable {
    let path: String
    let displayName: String
    let location: ValidationIssueLocation
    let inputMembers: Set<String>
}

struct SubContainerBindingValidationRecord: Equatable {
    let childInputName: String
    let parentMemberName: String
    let childLocation: ValidationIssueLocation
    let parentLocation: ValidationIssueLocation
}

struct SemanticSubContainerRecord: Equatable {
    let parentContainerPath: String
    let memberName: String
    let childReference: SemanticTypeReference?
    let bindings: [SubContainerBindingValidationRecord]
    let invalidBindingsLocation: ValidationIssueLocation?
}

struct DeferredWrapperParameterRecord: Equatable {
    let memberName: String
    let parameterName: String
    let writtenWrapperKind: DeferredDependencyWrapperKind?
    let headReference: SemanticTypeReference
    let location: ValidationIssueLocation
}

struct WrapperDeclarationRecord: Equatable {
    let path: String
    let wrapperKind: DeferredDependencyWrapperKind
    let location: ValidationIssueLocation
}

struct WrapperAliasRecord: Equatable {
    let path: String
    let targetHeadReference: SemanticTypeReference
    let location: ValidationIssueLocation
}

private final class ContainerSemanticFileCollector: SyntaxVisitor {
    private let filePath: String
    private let locationConverter: SourceLocationConverter
    private var declarationStack: [String] = []
    private var containerContextStack: [String?] = []
    private var containerBuilders: [String: SemanticContainerBuilder] = [:]

    private(set) var nominalTypes: [SemanticNominalTypeRecord] = []
    private(set) var typeAliases: [SemanticTypeAliasRecord] = []
    private(set) var subContainers: [SemanticSubContainerRecord] = []
    private(set) var wrapperParameters: [DeferredWrapperParameterRecord] = []
    private(set) var wrapperDeclarations: [WrapperDeclarationRecord] = []
    private(set) var wrapperAliases: [WrapperAliasRecord] = []

    var containers: [SemanticContainerRecord] {
        containerBuilders.values
            .map { builder in
                SemanticContainerRecord(
                    path: builder.path,
                    displayName: builder.path.split(separator: ".").last.map(String.init) ?? builder.path,
                    location: builder.location,
                    inputMembers: builder.inputMembers
                )
            }
            .sorted { $0.path < $1.path }
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
        let location = sourceLocation(for: node.positionAfterSkippingLeadingTrivia)

        if let targetReference = normalizedSemanticTypeReference(node.initializer.value) {
            typeAliases.append(
                SemanticTypeAliasRecord(
                    path: path,
                    components: components,
                    target: targetReference
                )
            )
        }

        if let wrapperKind = directWrapperKind(named: node.name.text) {
            wrapperDeclarations.append(
                WrapperDeclarationRecord(
                    path: path,
                    wrapperKind: wrapperKind,
                    location: location
                )
            )
        }

        if let targetHeadReference = genericTypeHeadReference(node.initializer.value) {
            wrapperAliases.append(
                WrapperAliasRecord(
                    path: path,
                    targetHeadReference: targetHeadReference,
                    location: location
                )
            )
        }

        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let currentContainerPath = containerContextStack.last ?? nil,
              isDirectMemberVariable(node),
              let binding = validatedSingleBinding(node) else {
            return .skipChildren
        }

        let managedSemantics = parseManagedMemberSemantics(node.attributes)

        if let provideAttribute = managedSemantics.provideAttributes.first {
            let provideArguments = managedSemantics.provideArguments
                ?? parseProvideArguments(provideAttribute)
            if provideArguments.scope == .input {
                containerBuilders[currentContainerPath, default: SemanticContainerBuilder(
                    path: currentContainerPath,
                    location: sourceLocation(for: node.positionAfterSkippingLeadingTrivia)
                )]
                .inputMembers.insert(binding.name)
            }

            collectDeferredWrapperParameters(
                from: provideArguments.factoryExpr?.as(ClosureExprSyntax.self),
                memberName: binding.name
            )
            collectDeferredWrapperParameters(
                from: provideArguments.asyncFactoryExpr?.as(ClosureExprSyntax.self),
                memberName: binding.name
            )
        }

        if let subContainerAttribute = managedSemantics.subContainerAttributes.first,
           let childType = binding.type {
            let subArguments = managedSemantics.subContainerArguments
                ?? parseSubContainerArguments(subContainerAttribute)
            let bindingParseState = extractBindingValidationRecords(from: subContainerAttribute)
            if subArguments.bindingsParseState.hasArgument {
                subContainers.append(
                    SemanticSubContainerRecord(
                        parentContainerPath: currentContainerPath,
                        memberName: binding.name,
                        childReference: normalizedSemanticTypeReference(childType),
                        bindings: bindingParseState.bindings,
                        invalidBindingsLocation: bindingParseState.invalidLocation
                    )
                )
            }
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
            SemanticNominalTypeRecord(
                path: declarationPath,
                components: declarationStack
            )
        )

        let location = sourceLocation(for: node.positionAfterSkippingLeadingTrivia)
        if let wrapperKind = directWrapperKind(named: name) {
            wrapperDeclarations.append(
                WrapperDeclarationRecord(
                    path: declarationPath,
                    wrapperKind: wrapperKind,
                    location: location
                )
            )
        }

        if containsDIContainerAttribute(node.attributes),
           classifyDIContainerDeclaration(node).isSupported {
            containerBuilders[declarationPath] = SemanticContainerBuilder(
                path: declarationPath,
                location: location
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

    private func collectDeferredWrapperParameters(
        from closure: ClosureExprSyntax?,
        memberName: String
    ) {
        guard let closure,
              let signature = closure.signature,
              let parameterClause = signature.parameterClause,
              case .parameterClause(let parameters) = parameterClause else {
            return
        }

        for parameter in parameters.parameters {
            let token = parameter.secondName ?? parameter.firstName
            let parameterName = token.text
            if parameterName == "_" {
                continue
            }

            guard let parameterType = parameter.type,
                  let headReference = genericTypeHeadReference(parameterType) else {
                continue
            }

            wrapperParameters.append(
                DeferredWrapperParameterRecord(
                    memberName: memberName,
                    parameterName: parameterName,
                    writtenWrapperKind: deferredDependencyWrapperKind(for: parameterType),
                    headReference: headReference,
                    location: sourceLocation(for: token.positionAfterSkippingLeadingTrivia)
                )
            )
        }
    }

    private func extractBindingValidationRecords(from attribute: AttributeSyntax) -> BindingValidationParseState {
        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
            return .omitted
        }

        for argument in arguments where argument.label?.text == "bindings" {
            guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self) else {
                return .invalid(sourceLocation(for: argument.expression.positionAfterSkippingLeadingTrivia))
            }

            var bindings: [SubContainerBindingValidationRecord] = []
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

                guard let childName, let parentName, let childLocation, let parentLocation else {
                    return .invalid(sourceLocation(for: element.expression.positionAfterSkippingLeadingTrivia))
                }

                bindings.append(SubContainerBindingValidationRecord(
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

private enum BindingValidationParseState {
    case omitted
    case parsed([SubContainerBindingValidationRecord])
    case invalid(ValidationIssueLocation)

    var bindings: [SubContainerBindingValidationRecord] {
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
}

private struct SemanticContainerBuilder {
    let path: String
    let location: ValidationIssueLocation
    var inputMembers: Set<String> = []
}

private struct ValidatedVariableBinding {
    let name: String
    let type: TypeSyntax?
}

private func validatedSingleBinding(_ varDecl: VariableDeclSyntax) -> ValidatedVariableBinding? {
    guard varDecl.bindings.count == 1,
          let binding = varDecl.bindings.first,
          let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
        return nil
    }

    return ValidatedVariableBinding(
        name: identifier.identifier.text,
        type: binding.typeAnnotation?.type
    )
}

private func isDirectMemberVariable(_ node: VariableDeclSyntax) -> Bool {
    node.parent?.is(MemberBlockItemSyntax.self) == true
}

private func containsDIContainerAttribute(_ attributes: AttributeListSyntax?) -> Bool {
    findDIContainerAttribute(in: attributes) != nil
}

private func directWrapperKind(named name: String) -> DeferredDependencyWrapperKind? {
    DeferredDependencyWrapperKind(rawValue: name)
}

func canonicalWrapperKind(for reference: SemanticTypeReference) -> DeferredDependencyWrapperKind? {
    guard reference.components.count == 2, reference.components.first == "InnoDI",
          let last = reference.components.last else {
        return nil
    }
    return DeferredDependencyWrapperKind(rawValue: last)
}

func resolveWrapperAliasKind(
    for path: String,
    aliasesByPath: [String: WrapperAliasRecord],
    visited: Set<String> = []
) -> DeferredDependencyWrapperKind? {
    guard !visited.contains(path),
          let aliasRecord = aliasesByPath[path] else {
        return nil
    }

    if let canonicalKind = canonicalWrapperKind(for: aliasRecord.targetHeadReference) {
        return canonicalKind
    }

    var nextVisited = visited
    nextVisited.insert(path)
    return resolveWrapperAliasKind(
        for: aliasRecord.targetHeadReference.displayPath,
        aliasesByPath: aliasesByPath,
        visited: nextVisited
    )
}

private func genericTypeHeadReference(_ type: TypeSyntax) -> SemanticTypeReference? {
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return genericTypeHeadReference(attributed.baseType)
    }

    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let first = tuple.elements.first,
       first.firstName == nil,
       first.secondName == nil {
        return genericTypeHeadReference(first.type)
    }

    if let identifier = type.as(IdentifierTypeSyntax.self) {
        guard identifier.genericArgumentClause?.arguments.count == 1 else {
            return nil
        }
        return SemanticTypeReference(
            displayPath: identifier.name.text,
            components: [identifier.name.text]
        )
    }

    if let member = type.as(MemberTypeSyntax.self),
       member.genericArgumentClause?.arguments.count == 1,
       let base = normalizedSemanticTypeReference(member.baseType) {
        let components = base.components + [member.name.text]
        return SemanticTypeReference(
            displayPath: components.joined(separator: "."),
            components: components
        )
    }

    return nil
}
