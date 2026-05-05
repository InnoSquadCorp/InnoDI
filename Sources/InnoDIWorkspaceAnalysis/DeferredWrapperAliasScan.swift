import Foundation
import SwiftSyntax

/// Kind of deferred wrapper a workspace `typealias` was renaming.
package enum DeferredWrapperAliasKind: String, Sendable {
    case lazy
    case provider
}

/// One workspace-wide finding for a `typealias` that aliases `Lazy<T>` or
/// `Provider<T>`. The macro resolves deferred-wrapper kinds by canonical
/// identifier at the factory parameter site, so an alias outside the factory's
/// own file silently behaves as a hard edge.
package struct DeferredWrapperAliasFinding: Sendable, Equatable {
    package let kind: DeferredWrapperAliasKind
    package let aliasName: String
    package let relativePath: String
    package let line: Int
    package let column: Int

    package init(
        kind: DeferredWrapperAliasKind,
        aliasName: String,
        relativePath: String,
        line: Int,
        column: Int
    ) {
        self.kind = kind
        self.aliasName = aliasName
        self.relativePath = relativePath
        self.line = line
        self.column = column
    }
}

/// Walk every source file in the snapshot and collect typealiases that
/// rename `Lazy<…>` or `Provider<…>`. Both bare (`Lazy`) and qualified
/// (`InnoDI.Lazy`) right-hand sides are detected. Cross-file findings are
/// the value-add over the same-file `DILazyProviderAliasCheck` that runs
/// inside the macro plugin: a typealias declared in a different module or
/// file would otherwise stay invisible.
package func scanDeferredWrapperAliases(
    in snapshot: WorkspaceSourceSnapshot
) -> [DeferredWrapperAliasFinding] {
    var findings: [DeferredWrapperAliasFinding] = []
    for file in snapshot.files {
        let visitor = DeferredWrapperAliasVisitor(
            relativePath: file.relativePath,
            locationConverter: SourceLocationConverter(
                fileName: file.relativePath,
                tree: file.syntax
            )
        )
        visitor.walk(file.syntax)
        findings.append(contentsOf: visitor.findings)
    }
    return findings
}

private final class DeferredWrapperAliasVisitor: SyntaxVisitor {
    let relativePath: String
    let locationConverter: SourceLocationConverter
    var findings: [DeferredWrapperAliasFinding] = []

    init(relativePath: String, locationConverter: SourceLocationConverter) {
        self.relativePath = relativePath
        self.locationConverter = locationConverter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let kind = deferredWrapperKind(of: node.initializer.value) else {
            return .skipChildren
        }
        let location = node.name.startLocation(converter: locationConverter)
        findings.append(
            DeferredWrapperAliasFinding(
                kind: kind,
                aliasName: node.name.text,
                relativePath: relativePath,
                line: location.line,
                column: location.column
            )
        )
        return .skipChildren
    }
}

private func deferredWrapperKind(of type: TypeSyntax) -> DeferredWrapperAliasKind? {
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return matchedKind(for: identifier.name.text)
    }
    if let member = type.as(MemberTypeSyntax.self) {
        // `InnoDI.Lazy<…>` and any other `Module.Lazy<…>`/`Module.Provider<…>`
        // qualified spelling. The macro accepts these as canonical so the
        // alias still hides the wrapper kind from the macro.
        return matchedKind(for: member.name.text)
    }
    return nil
}

private func matchedKind(for name: String) -> DeferredWrapperAliasKind? {
    switch name {
    case "Lazy": return .lazy
    case "Provider": return .provider
    default: return nil
    }
}
