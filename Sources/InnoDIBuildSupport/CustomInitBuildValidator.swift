import Foundation
import InnoDICore
import InnoDIWorkspaceAnalysis
import SwiftSyntax

package enum CustomInitBuildValidator {
    package static func validate(rootPath: String) throws -> ValidationIssueReport {
        try validate(snapshot: loadWorkspaceSourceSnapshot(rootPath: rootPath))
    }

    package static func validate(snapshot: WorkspaceSourceSnapshot) throws -> ValidationIssueReport {
        // A manifest snapshot holds every target the build can see, so an
        // unqualified path such as `Dependencies` can name a container in one
        // target and an unrelated type in another. An extension initializer
        // is a custom init only of a container declared in the extension's
        // own target: an initializer in another module's extension must
        // delegate through `self.init(...)` or `self = ...`, which reaches the
        // synthesized initializer. Each target's extensions therefore resolve
        // against that target's own declarations and aliases only. A
        // root-path snapshot is a single scope.
        var scopes: [String?] = []
        var recordsByScope: [String?: CustomInitScopeRecords] = [:]

        for sourceFile in snapshot.files {
            let collector = CustomInitFileCollector(
                filePath: sourceFile.filePath,
                syntax: sourceFile.syntax
            )
            collector.walk(sourceFile.syntax)

            let scope = sourceFile.targetID?.rawValue
            if recordsByScope[scope] == nil {
                scopes.append(scope)
            }
            recordsByScope[scope, default: CustomInitScopeRecords()].append(collector)
        }

        var issues: [ValidationIssue] = []
        for scope in scopes {
            guard let records = recordsByScope[scope] else {
                continue
            }
            issues.append(contentsOf: validate(records))
        }

        issues.sort {
            if $0.location.filePath != $1.location.filePath { return $0.location.filePath < $1.location.filePath }
            if $0.location.line != $1.location.line { return $0.location.line < $1.location.line }
            return $0.location.column < $1.location.column
        }

        return ValidationIssueReport(issues: issues)
    }

    private static func validate(_ records: CustomInitScopeRecords) -> [ValidationIssue] {
        let containersByPath = records.containersByPath
        let resolver = SemanticResolverIndex(
            nominalTypes: records.nominalTypes,
            topLevelTypeAliases: records.typeAliases
        )
        let candidatePaths = Set(containersByPath.keys)
        var issues: [ValidationIssue] = []

        for record in records.extensionRecords {
            let resolution = resolver.resolvePath(
                for: record.extendedTypeReference,
                candidatePaths: candidatePaths
            )

            let resolvedPath: String
            switch resolution.state {
            case .resolved:
                guard let path = resolution.resolvedPath else {
                    continue
                }
                resolvedPath = path
            case .ambiguous, .excluded, .unresolved:
                resolvedPath = record.extendedTypeReference.displayPath
            }

            // Attached declaration macros receive a detached declaration in
            // compiler-plugin builds, so they cannot reliably inspect sibling
            // extensions even when those extensions are in the same file.
            // The full-source preflight therefore owns every extension init,
            // not only cross-file declarations.
            guard let container = containersByPath[resolvedPath]?.first else {
                continue
            }

            for initializer in record.initializers {
                issues.append(
                    ValidationIssue(
                        code: MacroBuildDiagnosticContract
                            .containerCustomInitUnsupportedCode,
                        severity: .error,
                        message: MacroBuildDiagnosticContract
                            .containerCustomInitUnsupportedMessage,
                        location: ValidationIssueLocation(
                            filePath: record.filePath,
                            line: initializer.line,
                            column: initializer.column
                        ),
                        notes: [
                            ValidationIssueNote(
                                message: "container '\(container.declarationPath)' is declared here.",
                                location: ValidationIssueLocation(
                                    filePath: container.filePath,
                                    line: container.line,
                                    column: container.column
                                )
                            ),
                            ValidationIssueNote(
                                message: "The synthesized container initializer already covers @Input members and optional dependency overrides.",
                                location: ValidationIssueLocation(
                                    filePath: container.filePath,
                                    line: container.line,
                                    column: container.column
                                )
                            ),
                            ValidationIssueNote(
                                message: "Remove this custom initializer, or remove @DIContainer and wire the container manually."
                            )
                        ],
                        remediation: "Prefer the synthesized initializer for @Input members, or drop @DIContainer and keep the custom wiring manually.",
                        metadata: [
                            "containerPath": container.declarationPath,
                            "resolutionState": resolution.state.rawValue
                        ]
                    )
                )
            }
        }

        return issues
    }
}

/// Declarations collected from the files of one target.
private struct CustomInitScopeRecords {
    var containersByPath: [String: [ContainerDeclarationRecord]] = [:]
    var extensionRecords: [ExtensionInitializerRecord] = []
    var nominalTypes: [SemanticNominalTypeRecord] = []
    var typeAliases: [SemanticTypeAliasRecord] = []

    mutating func append(_ collector: CustomInitFileCollector) {
        for container in collector.containerDeclarations {
            containersByPath[container.declarationPath, default: []].append(container)
        }
        extensionRecords.append(contentsOf: collector.extensionInitializers)
        nominalTypes.append(contentsOf: collector.nominalTypes)
        typeAliases.append(contentsOf: collector.typeAliases)
    }
}

private struct ContainerDeclarationRecord: Equatable {
    let declarationPath: String
    let filePath: String
    let line: Int
    let column: Int
}

private struct ExtensionInitializerRecord: Equatable {
    struct InitializerLocation: Equatable {
        let line: Int
        let column: Int
    }

    let extendedTypeReference: SemanticTypeReference
    let filePath: String
    let initializers: [InitializerLocation]
}

private final class CustomInitFileCollector: SyntaxVisitor {
    private let filePath: String
    private let locationConverter: SourceLocationConverter
    private var declarationStack: [String] = []

    private(set) var containerDeclarations: [ContainerDeclarationRecord] = []
    private(set) var extensionInitializers: [ExtensionInitializerRecord] = []
    private(set) var nominalTypes: [SemanticNominalTypeRecord] = []
    private(set) var typeAliases: [SemanticTypeAliasRecord] = []

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

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let targetReference = normalizedSemanticTypeReference(node.initializer.value) else {
            return .skipChildren
        }

        let components = declarationStack + [node.name.text]
        let path = components.joined(separator: ".")

        typeAliases.append(
            SemanticTypeAliasRecord(
                path: path,
                components: components,
                target: targetReference
            )
        )
        return .skipChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.genericWhereClause == nil,
              let extendedTypeReference = normalizedSemanticTypeReference(node.extendedType) else {
            return .skipChildren
        }

        let initializers = directExtensionInitializers(
            in: node.memberBlock.members
        ).map { initializer in
            let location = locationConverter.location(for: initializer.positionAfterSkippingLeadingTrivia)
            return ExtensionInitializerRecord.InitializerLocation(
                line: location.line,
                column: location.column
            )
        }

        if !initializers.isEmpty {
            extensionInitializers.append(
                ExtensionInitializerRecord(
                    extendedTypeReference: extendedTypeReference,
                    filePath: filePath,
                    initializers: initializers
                )
            )
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

        if containsDIContainerAttribute(node.attributes),
           classifyDIContainerDeclaration(node).isSupported {
            let location = locationConverter.location(
                for: node.positionAfterSkippingLeadingTrivia
            )
            containerDeclarations.append(
                ContainerDeclarationRecord(
                    declarationPath: declarationPath,
                    filePath: filePath,
                    line: location.line,
                    column: location.column
                )
            )
        }

        return .visitChildren
    }

    private func visitPostNominal() {
        if !declarationStack.isEmpty {
            declarationStack.removeLast()
        }
    }
}

private func containsDIContainerAttribute(_ attributes: AttributeListSyntax?) -> Bool {
    findDIContainerAttribute(in: attributes) != nil
}

/// Extension members inside top-level conditional-compilation branches share
/// the extension's lookup scope. Nested declarations and executable bodies do
/// not, so stop recursion before entering either kind of body.
private func directExtensionInitializers(
    in members: MemberBlockItemListSyntax
) -> [InitializerDeclSyntax] {
    var result: [InitializerDeclSyntax] = []
    for member in members {
        collectDirectExtensionInitializers(
            in: Syntax(member.decl),
            into: &result
        )
    }
    return result
}

private func collectDirectExtensionInitializers(
    in syntax: Syntax,
    into result: inout [InitializerDeclSyntax]
) {
    if let initializer = syntax.as(InitializerDeclSyntax.self) {
        result.append(initializer)
        return
    }

    guard syntax.is(IfConfigDeclSyntax.self)
        || syntax.is(IfConfigClauseListSyntax.self)
        || syntax.is(IfConfigClauseSyntax.self)
        || syntax.is(MemberBlockItemSyntax.self)
        || syntax.is(MemberBlockItemListSyntax.self) else {
        return
    }
    for child in syntax.children(viewMode: .sourceAccurate) {
        collectDirectExtensionInitializers(in: child, into: &result)
    }
}
