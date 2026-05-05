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

    package static func validate(snapshot: WorkspaceSourceSnapshot) throws -> ValidationIssueReport {
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

        var issues: [ValidationIssue] = []

        for subContainer in subContainers {
            guard let childReference = subContainer.childReference else {
                continue
            }

            let resolution = semanticResolver.resolvePath(
                for: childReference,
                candidatePaths: containerCandidatePaths
            )
            guard resolution.state == .resolved,
                  let childPath = resolution.resolvedPath,
                  let childContainer = containerInputsByPath[childPath] else {
                continue
            }

            for binding in subContainer.bindings where !childContainer.inputMembers.contains(binding.childInputName) {
                issues.append(
                    ValidationIssue(
                        code: "sub.unknown-child-input",
                        severity: .error,
                        message: "@SubContainer on '\(subContainer.memberName)' binds child input '\(binding.childInputName)', but '\(childContainer.displayName)' does not declare a matching .input member.",
                        location: binding.childLocation,
                        notes: [
                            ValidationIssueNote(
                                message: "child container '\(childContainer.path)' is declared here.",
                                location: childContainer.location
                            )
                        ],
                        remediation: "Rename the child keypath in bindings:, or add a matching @Provide(.input) member to '\(childContainer.displayName)'.",
                        metadata: [
                            "childContainerPath": childContainer.path,
                            "parentContainerPath": subContainer.parentContainerPath
                        ]
                    )
                )
            }
        }

        for parameter in wrapperParameters {
            if let aliasKind = resolveWrapperAliasKind(
                for: parameter.headReference.displayPath,
                aliasesByPath: wrapperAliasesByPath
            ) {
                let aliasRecord = wrapperAliasesByPath[parameter.headReference.displayPath]
                issues.append(
                    ValidationIssue(
                        code: "provide.deferred-wrapper-alias-unsupported",
                        severity: .error,
                        message: "Factory parameter '\(parameter.parameterName)' for '\(parameter.memberName)' uses wrapper alias '\(parameter.headReference.displayPath)'. Wrapper aliases are not supported; spell `InnoDI.\(aliasKind.rawValue)<T>` directly.",
                        location: parameter.location,
                        notes: aliasRecord.map {
                            [
                                ValidationIssueNote(
                                    message: "alias '\($0.path)' is declared here.",
                                    location: $0.location
                                )
                            ]
                        } ?? [],
                        remediation: "Replace the alias use with `InnoDI.\(aliasKind.rawValue)<...>` in the factory parameter type annotation.",
                        metadata: [
                            "wrapperKind": aliasKind.rawValue,
                            "writtenHead": parameter.headReference.displayPath
                        ]
                    )
                )
                continue
            }

            guard let writtenWrapperKind = parameter.writtenWrapperKind else {
                continue
            }

            if canonicalWrapperKind(for: parameter.headReference) != nil {
                continue
            }

            if let exactLocalWrapper = wrapperDeclarationsByPath[parameter.headReference.displayPath],
               exactLocalWrapper.wrapperKind == writtenWrapperKind {
                issues.append(
                    ValidationIssue(
                        code: "provide.deferred-wrapper-qualification-required",
                        severity: .error,
                        message: "Factory parameter '\(parameter.parameterName)' for '\(parameter.memberName)' must spell `InnoDI.\(writtenWrapperKind.rawValue)<T>` explicitly. `\(parameter.headReference.displayPath)` resolves to a same-module declaration and is ambiguous for macro expansion.",
                        location: parameter.location,
                        notes: [
                            ValidationIssueNote(
                                message: "same-module declaration '\(exactLocalWrapper.path)' is defined here.",
                                location: exactLocalWrapper.location
                            )
                        ],
                        remediation: "Replace `\(parameter.headReference.displayPath)<...>` with `InnoDI.\(writtenWrapperKind.rawValue)<...>` at the factory parameter site.",
                        metadata: [
                            "wrapperKind": writtenWrapperKind.rawValue,
                            "writtenHead": parameter.headReference.displayPath
                        ]
                    )
                )
            }
        }

        issues.sort {
            if $0.location.filePath != $1.location.filePath { return $0.location.filePath < $1.location.filePath }
            if $0.location.line != $1.location.line { return $0.location.line < $1.location.line }
            return $0.location.column < $1.location.column
        }

        return ValidationIssueReport(issues: issues)
    }
}

private struct SemanticContainerRecord: Equatable {
    let path: String
    let displayName: String
    let location: ValidationIssueLocation
    let inputMembers: Set<String>
}

private struct SubContainerBindingValidationRecord: Equatable {
    let childInputName: String
    let parentMemberName: String
    let childLocation: ValidationIssueLocation
    let parentLocation: ValidationIssueLocation
}

private struct SemanticSubContainerRecord: Equatable {
    let parentContainerPath: String
    let memberName: String
    let childReference: SemanticTypeReference?
    let bindings: [SubContainerBindingValidationRecord]
}

private struct DeferredWrapperParameterRecord: Equatable {
    let memberName: String
    let parameterName: String
    let writtenWrapperKind: DeferredDependencyWrapperKind?
    let headReference: SemanticTypeReference
    let location: ValidationIssueLocation
}

private struct WrapperDeclarationRecord: Equatable {
    let path: String
    let wrapperKind: DeferredDependencyWrapperKind
    let location: ValidationIssueLocation
}

private struct WrapperAliasRecord: Equatable {
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

        if let provideAttribute = findInnoDIAttribute(named: "Provide", in: node.attributes) {
            let provideArguments = parseProvideArguments(provideAttribute)
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

        if let subContainerAttribute = findInnoDIAttribute(named: "SubContainer", in: node.attributes),
           let childType = binding.type {
            let subArguments = parseSubContainerArguments(subContainerAttribute)
            if !subArguments.bindings.isEmpty {
                subContainers.append(
                    SemanticSubContainerRecord(
                        parentContainerPath: currentContainerPath,
                        memberName: binding.name,
                        childReference: normalizedSemanticTypeReference(childType),
                        bindings: extractBindingValidationRecords(from: subContainerAttribute)
                    )
                )
            }
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

        if containsDIContainerAttribute(attributes) {
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

    private func extractBindingValidationRecords(from attribute: AttributeSyntax) -> [SubContainerBindingValidationRecord] {
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

                    switch label {
                    case "child":
                        childName = property
                        childLocation = sourceLocation(for: keyPath.positionAfterSkippingLeadingTrivia)
                    case "parent":
                        parentName = property
                        parentLocation = sourceLocation(for: keyPath.positionAfterSkippingLeadingTrivia)
                    default:
                        continue
                    }
                }

                guard let childName, let parentName, let childLocation, let parentLocation else {
                    return nil
                }

                return SubContainerBindingValidationRecord(
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
    findInnoDIAttribute(named: "DIContainer", in: attributes) != nil
}

private func directWrapperKind(named name: String) -> DeferredDependencyWrapperKind? {
    DeferredDependencyWrapperKind(rawValue: name)
}

private func canonicalWrapperKind(for reference: SemanticTypeReference) -> DeferredDependencyWrapperKind? {
    guard reference.components.count == 2, reference.components.first == "InnoDI",
          let last = reference.components.last else {
        return nil
    }
    return DeferredDependencyWrapperKind(rawValue: last)
}

private func wrapperKindCandidate(for reference: SemanticTypeReference) -> DeferredDependencyWrapperKind? {
    if let canonical = canonicalWrapperKind(for: reference) {
        return canonical
    }
    guard let last = reference.components.last else {
        return nil
    }
    return DeferredDependencyWrapperKind(rawValue: last)
}

private func resolveWrapperAliasKind(
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
