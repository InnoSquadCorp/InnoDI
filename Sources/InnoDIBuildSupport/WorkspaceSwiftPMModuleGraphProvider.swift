import Foundation
import SwiftParser
import SwiftSyntax

enum SwiftPMModuleGraphProvider {
    static func snapshot(
        from manifestURL: URL
    ) throws -> SwiftPMManifestSnapshot {
        let source = try String(contentsOf: manifestURL, encoding: .utf8)
        let syntax = Parser.parse(source: source)
        let collector = SwiftPMManifestCollector(manifestURL: manifestURL)
        collector.walk(syntax)
        return collector.snapshot
    }
}

struct SwiftPMManifestSnapshot {
    let modules: [WorkspaceModuleRecord]
    let products: [WorkspaceSwiftPMProductRecord]
}

private final class SwiftPMManifestCollector: SyntaxVisitor {
    private let manifestDirectoryURL: URL
    private let manifestPath: String
    private(set) var modules: [WorkspaceModuleRecord] = []
    private var packageDisplayName: String?
    private var packageIdentity: String
    private var packageDependencies: [
        WorkspaceSwiftPMPackageDependencyRecord
    ] = []
    private var productBuilders: [SwiftPMProductBuilder] = []

    init(manifestURL: URL) {
        manifestDirectoryURL = manifestURL.deletingLastPathComponent()
        manifestPath = NSString(
            string: manifestURL.path(percentEncoded: false)
        ).standardizingPath
        packageIdentity = normalizePackageIdentity(
            manifestURL.deletingLastPathComponent().lastPathComponent
        )
        super.init(viewMode: .sourceAccurate)
    }

    var snapshot: SwiftPMManifestSnapshot {
        let products = productBuilders.map { builder in
            WorkspaceSwiftPMProductRecord(
                productID: swiftPMProductID(
                    manifestPath: manifestPath,
                    productName: builder.productName
                ),
                productName: builder.productName,
                manifestPath: manifestPath,
                packageDisplayName: packageDisplayName,
                packageIdentity: packageIdentity,
                exportedModuleIDs: builder.targetNames.map {
                    workspaceModuleID(
                        buildSystem: "swiftpm",
                        manifestPath: manifestPath,
                        targetName: $0
                    )
                }
            )
        }
        return SwiftPMManifestSnapshot(modules: modules, products: products)
    }

    override func visit(
        _ node: FunctionCallExprSyntax
    ) -> SyntaxVisitorContinueKind {
        if let declReference = node.calledExpression.as(
            DeclReferenceExprSyntax.self
        ),
           declReference.baseName.text == "Package" {
            packageDisplayName = labeledStringArgument(
                "name",
                in: node.arguments
            )
            packageIdentity = normalizePackageIdentity(
                packageDisplayName
                    ?? manifestDirectoryURL.lastPathComponent
            )
            packageDependencies = parseSwiftPMPackageDependencies(
                from: labeledExpression(
                    "dependencies",
                    in: node.arguments
                ),
                manifestDirectoryURL: manifestDirectoryURL
            )
            productBuilders = parseSwiftPMProducts(
                from: labeledExpression("products", in: node.arguments)
            )
            return .visitChildren
        }

        guard let memberAccess = node.calledExpression.as(
            MemberAccessExprSyntax.self
        ),
              memberAccess.base == nil else {
            return .visitChildren
        }

        let kind = memberAccess.declName.baseName.text
        guard ["target", "executableTarget", "macro", "testTarget"]
            .contains(kind) else {
            return .visitChildren
        }
        guard let name = labeledStringArgument(
            "name",
            in: node.arguments
        ) else {
            return .visitChildren
        }

        let dependencies = parseSwiftPMDependencyRefs(
            from: labeledExpression("dependencies", in: node.arguments),
            manifestPath: manifestPath
        )
        let explicitSources = parseStringArray(
            from: labeledExpression("sources", in: node.arguments)
        )
        let explicitPath = labeledStringArgument(
            "path",
            in: node.arguments
        )
        let defaultDirectory = kind == "testTarget"
            ? "Tests/\(name)"
            : "Sources/\(name)"
        let targetDirectoryURL = manifestDirectoryURL.appendingPathComponent(
            explicitPath ?? defaultDirectory
        )

        let sourcePatterns: [String]
        if !explicitSources.isEmpty {
            sourcePatterns = explicitSources.map {
                normalizeGlobPath($0, baseURL: targetDirectoryURL)
            }
        } else if let explicitPath {
            sourcePatterns = [
                normalizeGlobPath(
                    explicitPath,
                    baseURL: manifestDirectoryURL
                )
            ]
        } else {
            sourcePatterns = [
                normalizeGlobPath(
                    defaultDirectory,
                    baseURL: manifestDirectoryURL
                )
            ]
        }

        modules.append(
            WorkspaceModuleRecord(
                moduleID: workspaceModuleID(
                    buildSystem: "swiftpm",
                    manifestPath: manifestPath,
                    targetName: name
                ),
                name: name,
                manifestPath: manifestPath,
                packageDisplayName: packageDisplayName,
                packageIdentity: packageIdentity,
                sourcePatterns: sourcePatterns,
                dependencyRefs: dependencies,
                swiftPMPackageDependencies: packageDependencies,
                buildSystem: "swiftpm"
            )
        )
        return .skipChildren
    }
}

private struct SwiftPMProductBuilder {
    let productName: String
    let targetNames: [String]
}

private func swiftPMProductID(
    manifestPath: String,
    productName: String
) -> String {
    "\(manifestPath)|product|\(productName)"
}

private func parseSwiftPMPackageDependencies(
    from expression: ExprSyntax?,
    manifestDirectoryURL: URL
) -> [WorkspaceSwiftPMPackageDependencyRecord] {
    guard let arrayExpr = expression?.as(ArrayExprSyntax.self) else {
        return []
    }

    return arrayExpr.elements.compactMap { element in
        guard let call = element.expression.as(
            FunctionCallExprSyntax.self
        ) else {
            return nil
        }

        let explicitName = labeledStringArgument("name", in: call.arguments)
        let localPath = labeledStringArgument("path", in: call.arguments)
        let url = labeledStringArgument("url", in: call.arguments)
        let resolvedManifestPath = localPath.map { path in
            NSString(
                string: manifestDirectoryURL
                    .appendingPathComponent(path)
                    .appendingPathComponent("Package.swift")
                    .path(percentEncoded: false)
            ).standardizingPath
        }
        let inferredIdentitySource = explicitName
            ?? localPath.map {
                URL(fileURLWithPath: $0).lastPathComponent
            }
            ?? url.map {
                URL(string: $0)?.deletingPathExtension().lastPathComponent
                    ?? $0
            }
        let referenceNames = [explicitName, inferredIdentitySource]
            .compactMap { $0 }
            .map(normalizePackageIdentity)
        return WorkspaceSwiftPMPackageDependencyRecord(
            referenceNames: Array(Set(referenceNames)).sorted(),
            resolvedManifestPath: resolvedManifestPath
        )
    }
}

private func parseSwiftPMProducts(
    from expression: ExprSyntax?
) -> [SwiftPMProductBuilder] {
    guard let arrayExpr = expression?.as(ArrayExprSyntax.self) else {
        return []
    }

    return arrayExpr.elements.compactMap { element in
        guard let call = element.expression.as(
            FunctionCallExprSyntax.self
        ),
              let productName = labeledStringArgument(
                "name",
                in: call.arguments
              ) else {
            return nil
        }
        return SwiftPMProductBuilder(
            productName: productName,
            targetNames: parseStringArray(
                from: labeledExpression("targets", in: call.arguments)
            )
        )
    }
}

private func parseSwiftPMDependencyRefs(
    from expression: ExprSyntax?,
    manifestPath: String
) -> [WorkspaceModuleDependencyRef] {
    guard let arrayExpr = expression?.as(ArrayExprSyntax.self) else {
        return []
    }

    return arrayExpr.elements.compactMap { element in
        if let literal = stringLiteralValue(element.expression) {
            return WorkspaceModuleDependencyRef(
                kind: .unqualifiedSwiftPMDependency,
                targetName: literal,
                packageReference: nil,
                manifestPath: manifestPath
            )
        }

        guard let call = element.expression.as(
            FunctionCallExprSyntax.self
        ) else {
            return nil
        }
        let targetName = labeledStringArgument("name", in: call.arguments)
            ?? labeledStringArgument("target", in: call.arguments)
        guard let targetName else {
            return nil
        }

        if let memberAccess = call.calledExpression.as(
            MemberAccessExprSyntax.self
        ) {
            switch memberAccess.declName.baseName.text {
            case "product":
                return WorkspaceModuleDependencyRef(
                    kind: .swiftPMProduct,
                    targetName: targetName,
                    packageReference: labeledStringArgument(
                        "package",
                        in: call.arguments
                    ),
                    manifestPath: nil
                )
            case "target":
                return WorkspaceModuleDependencyRef(
                    kind: .localTarget,
                    targetName: targetName,
                    packageReference: nil,
                    manifestPath: manifestPath
                )
            case "byName":
                return WorkspaceModuleDependencyRef(
                    kind: .unqualifiedSwiftPMDependency,
                    targetName: targetName,
                    packageReference: nil,
                    manifestPath: manifestPath
                )
            default:
                break
            }
        }

        return WorkspaceModuleDependencyRef(
            kind: .unqualifiedSwiftPMDependency,
            targetName: targetName,
            packageReference: nil,
            manifestPath: manifestPath
        )
    }
}
