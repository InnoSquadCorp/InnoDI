//
//  DILazyProviderAliasCheck.swift
//  InnoDIMacros
//
//  Phase N-4 — warns when a closure parameter types a `typealias` that
//  aliases `Lazy<T>` or `Provider<T>`.
//
//  The macro resolves deferred-wrapper kinds purely from written syntax
//  (see `DeferredDependencyWrappers.deferredDependencyWrapperKind`), so an
//  alias like `typealias L = InnoDI.Lazy<Foo>` is silently treated as a
//  hard edge. That means a cycle users thought they broke with `Lazy<T>`
//  can still trigger `container.dependency-cycle`, and a Provider-aliased
//  target escapes the `.transient`-scope rule. Emitting a warning lets
//  authors catch the mistake before the surprising diagnostic (or the
//  even more surprising runtime behavior) bites.
//
//  Detection is best-effort: we walk the parent source file for
//  `typealias` declarations whose right-hand side reduces to
//  `Lazy<...>` / `Provider<...>` (bare or qualified `InnoDI.Lazy<...>` /
//  `InnoDI.Provider<...>`). Cross-file aliases stay invisible and are
//  skipped silently.
//

import InnoDICore
import SwiftSyntax

internal struct LazyProviderAliasMap {
    let lazyAliases: Set<String>
    let providerAliases: Set<String>

    var isEmpty: Bool { lazyAliases.isEmpty && providerAliases.isEmpty }
}

internal func collectLazyProviderAliases(anchoredBy syntax: Syntax) -> LazyProviderAliasMap {
    guard let sourceFile = sourceFileSyntax(containing: syntax) else {
        return LazyProviderAliasMap(lazyAliases: [], providerAliases: [])
    }

    var lazyAliases: Set<String> = []
    var providerAliases: Set<String> = []

    // NOTE: only source-file-top-level `typealias` decls are collected.
    // Nested alias chains (`typealias A = Lazy<T>; typealias B = A`) are
    // deliberately not followed — we only flag the leaf-RHS that we can
    // statically recognize as `Lazy<...>` / `Provider<...>`. Typealiases
    // inside type bodies and cross-file aliases are also invisible,
    // consistent with the rest of the macro's "best-effort, same-file"
    // detection contract.
    for statement in sourceFile.statements {
        guard case let .decl(decl) = statement.item,
              let typealiasDecl = decl.as(TypeAliasDeclSyntax.self) else {
            continue
        }

        let rhs = typealiasDecl.initializer.value
        if let kind = deferredDependencyWrapperKind(for: rhs) {
            let aliasName = typealiasDecl.name.text
            switch kind {
            case .lazy:
                lazyAliases.insert(aliasName)
            case .provider:
                providerAliases.insert(aliasName)
            }
        }
    }

    return LazyProviderAliasMap(lazyAliases: lazyAliases, providerAliases: providerAliases)
}

/// Returns the deferred-wrapper kind a factory parameter *would* have been
/// classified as, had the macro been able to resolve the alias. Used only
/// for emitting the warning — does NOT change edge classification downstream.
///
/// Only identifiers that are exact alias matches (bare `IdentifierTypeSyntax`)
/// are reported. Qualified `Module.Alias<T>` uses stay outside the warning
/// surface since they already force the author to think about module names.
internal func aliasedDeferredWrapperKind(
    for type: TypeSyntax?,
    aliases: LazyProviderAliasMap
) -> DeferredDependencyWrapperKind? {
    guard let type, !aliases.isEmpty else { return nil }

    // Only interested in plain `IdentifierTypeSyntax` names. If the macro
    // already recognized the type as Lazy/Provider, `deferredDependencyWrapperKind`
    // returns non-nil and we do not want to warn.
    if deferredDependencyWrapperKind(for: type) != nil {
        return nil
    }

    // Accepts both non-generic aliases (`typealias FooLazy = Lazy<Foo>` used
    // as `FooLazy`) and generic aliases (`typealias L<T> = Lazy<T>` used as
    // `L<Foo>`). Both spell the alias name at the leading identifier.
    let normalized = stripAttributesAndTuples(type)
    guard let identifier = normalized.as(IdentifierTypeSyntax.self) else {
        return nil
    }
    let name = identifier.name.text

    if aliases.lazyAliases.contains(name) {
        return .lazy
    }
    if aliases.providerAliases.contains(name) {
        return .provider
    }
    return nil
}

/// Strips attribute wrappers (`@escaping`, etc.) and single-element tuples
/// around the written type. Intentionally does NOT strip optional wrappers
/// (`T?`, `T!`, `Optional<T>`): `Lazy<T>?` is already rejected upstream by
/// `deferredDependencyWrapperKind`, and applying the alias warning to
/// optional aliases would be noise on an already-niche shape.
private func stripAttributesAndTuples(_ type: TypeSyntax) -> TypeSyntax {
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return stripAttributesAndTuples(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let first = tuple.elements.first,
       first.firstName == nil,
       first.secondName == nil {
        return stripAttributesAndTuples(first.type)
    }
    return type
}
