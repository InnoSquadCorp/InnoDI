import Foundation
import SwiftSyntax

/// Kind of deferred wrapper a workspace `typealias` was renaming.
package enum DeferredWrapperAliasKind: String, Sendable {
    case lazy
    case provider
}

/// One workspace-wide finding for a `typealias` that names `Lazy<T>` or
/// `Provider<T>`. The macro resolves deferred-wrapper kinds by the written
/// identifier at the factory parameter site and never resolves aliases, so a
/// parameter spelled with such an alias, in any file, behaves as a hard edge.
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

/// Modules whose qualified `Lazy` / `Provider` spelling names InnoDI's
/// wrapper: InnoDI itself and the products that re-export it.
private let deferredWrapperModuleNames: Set<String> = [
    "InnoDI",
    "InnoDISwiftUI",
    "InnoDITesting"
]

/// Collects every `typealias` that can stand in for `Lazy<T>` or
/// `Provider<T>` at a factory parameter.
///
/// A factory parameter's type is written in a container's attribute, so any
/// alias visible there qualifies: one at file scope or inside a type or
/// extension body. An alias inside a function, closure, or accessor body is
/// local and can never be named at a factory parameter, so it is ignored.
///
/// An alias qualifies when its right-hand side, ignoring attributes and
/// redundant parentheses, is `Lazy` / `Provider` (with or without generic
/// arguments), the same name qualified by `InnoDI` or a module that
/// re-exports it, or another qualifying alias. Alias chains are followed by
/// lexical scope through plain and type-qualified alias names; an alias
/// reached only through another module's name is not. A type merely named
/// `Provider` inside some other type, such as `Vendor.Provider`, is not
/// InnoDI's wrapper. In a real build the macro-level
/// `DILazyProviderAliasCheck` receives only the attached container
/// declaration, so this scan is the only place such an alias is reported.
package func scanDeferredWrapperAliases(
    in snapshot: WorkspaceSourceSnapshot
) -> [DeferredWrapperAliasFinding] {
    var declarations: [DeferredWrapperAliasDeclaration] = []
    var nominalPaths: Set<String> = []
    for file in snapshot.files {
        let visitor = DeferredWrapperAliasVisitor(
            relativePath: file.relativePath,
            locationConverter: SourceLocationConverter(
                fileName: file.relativePath,
                tree: file.syntax
            )
        )
        visitor.walk(file.syntax)
        declarations.append(contentsOf: visitor.declarations)
        nominalPaths.formUnion(visitor.nominalPaths)
    }

    let kinds = resolvedDeferredWrapperKinds(
        declarations: declarations,
        nominalPaths: nominalPaths
    )
    return declarations.indices.compactMap { index in
        guard let kind = kinds[index] else {
            return nil
        }
        let declaration = declarations[index]
        return DeferredWrapperAliasFinding(
            kind: kind,
            aliasName: declaration.name,
            relativePath: declaration.relativePath,
            line: declaration.line,
            column: declaration.column
        )
    }
}

private struct DeferredWrapperAliasDeclaration {
    let scope: [String]
    let name: String
    let target: DeferredWrapperAliasTarget
    let relativePath: String
    let line: Int
    let column: Int

    var qualifiedPath: String {
        (scope + [name]).joined(separator: ".")
    }
}

private enum DeferredWrapperAliasTarget {
    case wrapper(DeferredWrapperAliasKind)
    /// Root-relative qualified paths the right-hand side may name, innermost
    /// lexical scope first.
    case reference([String])
    case unrelated
}

/// Marks each declaration that is, directly or through a chain, an alias of
/// a deferred wrapper. Iterates to a fixed point so chain order and file
/// order do not matter.
private func resolvedDeferredWrapperKinds(
    declarations: [DeferredWrapperAliasDeclaration],
    nominalPaths: Set<String>
) -> [Int: DeferredWrapperAliasKind] {
    var kinds: [Int: DeferredWrapperAliasKind] = [:]
    var indicesByPath: [String: [Int]] = [:]
    for (index, declaration) in declarations.enumerated() {
        indicesByPath[declaration.qualifiedPath, default: []].append(index)
        if case .wrapper(let kind) = declaration.target {
            kinds[index] = kind
        }
    }

    var changed = true
    while changed {
        changed = false
        for (index, declaration) in declarations.enumerated()
        where kinds[index] == nil {
            guard case .reference(let candidatePaths) = declaration.target
            else {
                continue
            }
            for path in candidatePaths {
                if let matches = indicesByPath[path] {
                    // The innermost alias of that name shadows outer ones,
                    // whether or not it is (yet) known to be a wrapper.
                    if let kind = matches.lazy.compactMap({ kinds[$0] }).first {
                        kinds[index] = kind
                        changed = true
                    }
                    break
                }
                if nominalPaths.contains(path) {
                    // A nominal type of that name shadows outer aliases.
                    break
                }
            }
        }
    }
    return kinds
}

private final class DeferredWrapperAliasVisitor: SyntaxVisitor {
    let relativePath: String
    let locationConverter: SourceLocationConverter
    var declarations: [DeferredWrapperAliasDeclaration] = []
    var nominalPaths: Set<String> = []
    private var scope: [String] = []
    /// Per-declaration count of scope components pushed, so `visitPost`
    /// pops exactly what `visit` pushed.
    private var pushedComponentCounts: [Int] = []

    init(relativePath: String, locationConverter: SourceLocationConverter) {
        self.relativePath = relativePath
        self.locationConverter = locationConverter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = node.name.startLocation(converter: locationConverter)
        declarations.append(
            DeferredWrapperAliasDeclaration(
                scope: scope,
                name: node.name.text,
                target: deferredWrapperAliasTarget(
                    of: node.initializer.value,
                    scope: scope
                ),
                relativePath: relativePath,
                line: location.line,
                column: location.column
            )
        )
        return .skipChildren
    }

    // Local scopes: an alias declared here is invisible to a container's
    // attributes, and so are the members of a local type.
    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominal(node.name.text)
    }

    override func visitPost(_ node: StructDeclSyntax) {
        leaveScope()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominal(node.name.text)
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        leaveScope()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominal(node.name.text)
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        leaveScope()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominal(node.name.text)
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        leaveScope()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominal(node.name.text)
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        leaveScope()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let components = deferredWrapperTypeComponents(node.extendedType)
            ?? [node.extendedType.trimmedDescription]
        scope.append(contentsOf: components)
        pushedComponentCounts.append(components.count)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        leaveScope()
    }

    private func enterNominal(_ name: String) -> SyntaxVisitorContinueKind {
        scope.append(name)
        pushedComponentCounts.append(1)
        nominalPaths.insert(scope.joined(separator: "."))
        return .visitChildren
    }

    private func leaveScope() {
        let count = pushedComponentCounts.popLast() ?? 0
        scope.removeLast(min(count, scope.count))
    }
}

private func deferredWrapperAliasTarget(
    of type: TypeSyntax,
    scope: [String]
) -> DeferredWrapperAliasTarget {
    let normalized = deferredWrapperUnparenthesized(type)
    guard let components = deferredWrapperTypeComponents(normalized) else {
        return .unrelated
    }

    if components.count == 1, let kind = matchedKind(for: components[0]) {
        return .wrapper(kind)
    }
    if components.count == 2,
       deferredWrapperModuleNames.contains(components[0]),
       let kind = matchedKind(for: components[1]) {
        return .wrapper(kind)
    }

    let candidatePaths = stride(from: scope.count, through: 0, by: -1).map {
        (Array(scope.prefix($0)) + components).joined(separator: ".")
    }
    return .reference(candidatePaths)
}

/// Strips attributes and single-element unlabeled parentheses, which do not
/// change the named type: `(Lazy<Int>)` is `Lazy<Int>`.
private func deferredWrapperUnparenthesized(_ type: TypeSyntax) -> TypeSyntax {
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return deferredWrapperUnparenthesized(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let first = tuple.elements.first,
       first.firstName == nil,
       first.secondName == nil,
       first.ellipsis == nil {
        return deferredWrapperUnparenthesized(first.type)
    }
    return type
}

/// Name components of a plain or member type, ignoring generic arguments:
/// `Box<Int>.Item` is `["Box", "Item"]`. Returns `nil` for any other shape.
private func deferredWrapperTypeComponents(_ type: TypeSyntax) -> [String]? {
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return [identifier.name.text]
    }
    if let member = type.as(MemberTypeSyntax.self),
       let base = deferredWrapperTypeComponents(member.baseType) {
        return base + [member.name.text]
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
