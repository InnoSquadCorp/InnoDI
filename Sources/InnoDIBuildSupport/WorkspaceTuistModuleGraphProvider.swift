import Foundation
import SwiftParser
import SwiftSyntax

enum TuistModuleGraphProvider {
    static func modules(
        from manifestURL: URL
    ) throws -> [WorkspaceModuleRecord] {
        let source = try String(contentsOf: manifestURL, encoding: .utf8)
        let syntax = Parser.parse(source: source)
        let collector = TuistManifestCollector(manifestURL: manifestURL)
        collector.walk(syntax)
        return collector.modules
    }
}

private final class TuistManifestCollector: SyntaxVisitor {
    private let manifestDirectoryURL: URL
    private let manifestPath: String
    private(set) var modules: [WorkspaceModuleRecord] = []

    init(manifestURL: URL) {
        manifestDirectoryURL = manifestURL.deletingLastPathComponent()
        manifestPath = NSString(
            string: manifestURL.path(percentEncoded: false)
        ).standardizingPath
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(
        _ node: FunctionCallExprSyntax
    ) -> SyntaxVisitorContinueKind {
        guard isTuistTargetCall(node) else {
            return .visitChildren
        }
        guard let name = labeledStringArgument(
            "name",
            in: node.arguments
        ) else {
            return .visitChildren
        }

        let sources = parseStringArray(
            from: labeledExpression("sources", in: node.arguments)
        )
        let dependencies = parseTuistDependencyRefs(
            from: labeledExpression("dependencies", in: node.arguments),
            manifestDirectoryURL: manifestDirectoryURL,
            manifestPath: manifestPath
        )
        let sourcePatterns = (sources.isEmpty ? ["Sources/**"] : sources)
            .map {
                normalizeGlobPath($0, baseURL: manifestDirectoryURL)
            }

        modules.append(
            WorkspaceModuleRecord(
                moduleID: workspaceModuleID(
                    buildSystem: "tuist",
                    manifestPath: manifestPath,
                    targetName: name
                ),
                name: name,
                manifestPath: manifestPath,
                packageDisplayName: nil,
                packageIdentity: nil,
                sourcePatterns: sourcePatterns,
                dependencyRefs: dependencies,
                swiftPMPackageDependencies: [],
                buildSystem: "tuist"
            )
        )
        return .skipChildren
    }
}

private func parseTuistDependencyRefs(
    from expression: ExprSyntax?,
    manifestDirectoryURL: URL,
    manifestPath: String
) -> [WorkspaceModuleDependencyRef] {
    guard let arrayExpr = expression?.as(ArrayExprSyntax.self) else {
        return []
    }

    return arrayExpr.elements.compactMap { element in
        guard let call = element.expression.as(
            FunctionCallExprSyntax.self
        ) else {
            return nil
        }

        let calledName: String?
        if let memberAccess = call.calledExpression.as(
            MemberAccessExprSyntax.self
        ) {
            calledName = memberAccess.declName.baseName.text
        } else if let declReference = call.calledExpression.as(
            DeclReferenceExprSyntax.self
        ) {
            calledName = declReference.baseName.text
        } else {
            calledName = nil
        }

        switch calledName {
        case "target":
            guard let targetName = labeledStringArgument(
                "name",
                in: call.arguments
            ) else {
                return nil
            }
            return WorkspaceModuleDependencyRef(
                kind: .localTarget,
                targetName: targetName,
                packageReference: nil,
                manifestPath: manifestPath
            )

        case "project":
            guard let targetName = labeledStringArgument(
                "target",
                in: call.arguments
            ) ?? labeledStringArgument("name", in: call.arguments),
                  let projectPath = labeledStringArgument(
                    "path",
                    in: call.arguments
                  ) else {
                return nil
            }
            let resolvedManifestPath = NSString(
                string: manifestDirectoryURL
                    .appendingPathComponent(projectPath)
                    .appendingPathComponent("Project.swift")
                    .path(percentEncoded: false)
            ).standardizingPath
            return WorkspaceModuleDependencyRef(
                kind: .tuistProject,
                targetName: targetName,
                packageReference: nil,
                manifestPath: resolvedManifestPath
            )

        default:
            return nil
        }
    }
}

private func isTuistTargetCall(_ node: FunctionCallExprSyntax) -> Bool {
    if let memberAccess = node.calledExpression.as(
        MemberAccessExprSyntax.self
    ),
       memberAccess.declName.baseName.text == "target" {
        return true
    }
    if let declReference = node.calledExpression.as(
        DeclReferenceExprSyntax.self
    ),
       declReference.baseName.text == "Target" {
        return true
    }
    return false
}
