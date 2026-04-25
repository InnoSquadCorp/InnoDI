//
//  SyntaxBuilders.swift
//  InnoDIMacros
//
//  Shared SwiftSyntaxBuilder primitives used by `DIContainerCodeGenerator` and
//  `ProvideMacro` to emit macro output directly as typed AST nodes. Prefer these
//  helpers over string-interpolated `DeclSyntax`/`StmtSyntax` literals so that
//  trivia and structure are locked in at compile time.
//
//  Note: these builders must be self-sufficient even when their output is
//  rendered via raw `.description` (e.g. from `ProvideMacro` accessor tests
//  that compare against exact strings). The AST therefore attaches explicit
//  whitespace trivia to tokens wherever the old string-parsed equivalent
//  would have produced spaces.
//

import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Local bindings

/// Assembles a `let <bindingName> = <valueName>` local binding `DeclSyntax`
/// with `SwiftSyntaxBuilder`. Building the AST directly (instead of using
/// string interpolation) avoids trivia differences in the emitted output.
internal func letBinding(name bindingName: String, value valueName: String) -> DeclSyntax {
    let valueExpr = ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(valueName)))
    return letBinding(name: bindingName, value: valueExpr)
}

/// Creates a `let <bindingName> = <value>` binding with an arbitrary
/// expression as the value.
internal func letBinding(name bindingName: String, value: ExprSyntax) -> DeclSyntax {
    DeclSyntax(
        VariableDeclSyntax(
            bindingSpecifier: .keyword(.let, trailingTrivia: .space),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(bindingName)),
                    initializer: InitializerClauseSyntax(
                        equal: .equalToken(leadingTrivia: .space, trailingTrivia: .space),
                        value: value
                    )
                )
            ])
        )
    )
}

// MARK: - Storage peer declarations

/// Builds a `private let <name>: <type>` (or `: <type>?`) peer decl — the
/// canonical storage field shape emitted by the `@Provide` macro.
internal func storagePeerDecl(
    name: String,
    type: TypeSyntax,
    optional: Bool
) -> DeclSyntax {
    let storedType: TypeSyntax = optional
        ? TypeSyntax(OptionalTypeSyntax(wrappedType: type.trimmed))
        : type.trimmed

    let decl = VariableDeclSyntax(
        modifiers: DeclModifierListSyntax([
            DeclModifierSyntax(name: .keyword(.private, trailingTrivia: .space))
        ]),
        bindingSpecifier: .keyword(.let, trailingTrivia: .space),
        bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier(name)),
                typeAnnotation: TypeAnnotationSyntax(
                    colon: .colonToken(trailingTrivia: .space),
                    type: storedType
                )
            )
        ])
    )
    return DeclSyntax(decl)
}

/// Builds the peer decl for async-shared storage in the shape
/// `private let <name>: Task<<successType>, <failureType>>`.
internal func taskStoragePeerDecl(
    name: String,
    successType: String,
    failureType: String
) -> DeclSyntax {
    let genericClause = GenericArgumentClauseSyntax(
        arguments: GenericArgumentListSyntax([
            GenericArgumentSyntax(
                argument: .type(TypeSyntax("\(raw: successType)")),
                trailingComma: .commaToken(trailingTrivia: .space)
            ),
            GenericArgumentSyntax(argument: .type(TypeSyntax("\(raw: failureType)")))
        ])
    )
    let taskType = TypeSyntax(
        IdentifierTypeSyntax(
            name: .identifier("Task"),
            genericArgumentClause: genericClause
        )
    )

    let decl = VariableDeclSyntax(
        modifiers: DeclModifierListSyntax([
            DeclModifierSyntax(name: .keyword(.private, trailingTrivia: .space))
        ]),
        bindingSpecifier: .keyword(.let, trailingTrivia: .space),
        bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier(name)),
                typeAnnotation: TypeAnnotationSyntax(
                    colon: .colonToken(trailingTrivia: .space),
                    type: taskType
                )
            )
        ])
    )
    return DeclSyntax(decl)
}

/// Builds a peer decl in the shape
/// `private let _innoDISubBuild_<name>: @Sendable () -> <ChildType>`.
internal func subContainerBuildClosurePeerDecl(
    name: String,
    childType: TypeSyntax,
    isMainActor: Bool
) -> DeclSyntax {
    let attributes = AttributeListSyntax(
        [
            isMainActor
                ? AttributeListSyntax.Element.attribute(
                    AttributeSyntax(
                        attributeName: IdentifierTypeSyntax(
                            name: .identifier("MainActor", trailingTrivia: .space)
                        )
                    )
                )
                : nil,
            AttributeListSyntax.Element.attribute(
                AttributeSyntax(
                    attributeName: IdentifierTypeSyntax(
                        name: .identifier("Sendable", trailingTrivia: .space)
                    )
                )
            ),
        ].compactMap { $0 }
    )
    let functionType = TypeSyntax(
        AttributedTypeSyntax(
            specifiers: TypeSpecifierListSyntax([]),
            attributes: attributes,
            lateSpecifiers: TypeSpecifierListSyntax([]),
            baseType: FunctionTypeSyntax(
                parameters: TupleTypeElementListSyntax([]),
                returnClause: ReturnClauseSyntax(type: childType.trimmed)
            )
        )
    )

    let decl = VariableDeclSyntax(
        modifiers: DeclModifierListSyntax([
            DeclModifierSyntax(name: .keyword(.private, trailingTrivia: .space))
        ]),
        bindingSpecifier: .keyword(.let, trailingTrivia: .space),
        bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier("_innoDISubBuild_\(name)")),
                typeAnnotation: TypeAnnotationSyntax(
                    colon: .colonToken(trailingTrivia: .space),
                    type: functionType
                )
            )
        ])
    )
    return DeclSyntax(decl)
}

// MARK: - Statements

/// Builds a `CodeBlockItemSyntax` for a `return <expr>` statement.
internal func returnStmt(expr: ExprSyntax) -> CodeBlockItemSyntax {
    let ret = ReturnStmtSyntax(
        returnKeyword: .keyword(.return, trailingTrivia: .space),
        expression: expr
    )
    return CodeBlockItemSyntax(item: .stmt(StmtSyntax(ret)))
}

/// Builds a `CodeBlockItemSyntax` for `return [try] await <expr>`. When
/// `isThrowing` is `true`, the expression is wrapped in `try await`;
/// otherwise only `await` is applied.
internal func awaitedReturnStmt(expr: ExprSyntax, isThrowing: Bool) -> CodeBlockItemSyntax {
    let awaited = ExprSyntax(AwaitExprSyntax(
        awaitKeyword: .keyword(.await, trailingTrivia: .space),
        expression: expr
    ))
    let wrapped: ExprSyntax = isThrowing
        ? ExprSyntax(TryExprSyntax(
            tryKeyword: .keyword(.try, trailingTrivia: .space),
            expression: awaited
        ))
        : awaited
    return returnStmt(expr: wrapped)
}

/// Builds a `CodeBlockItemSyntax` for
/// `if let override = <overrideName> { return override }`. Emitted on the
/// override branch of `@Provide(.transient, ...)` accessors.
internal func overrideCheckStmt(overrideName: String) -> CodeBlockItemSyntax {
    let ifStmt = IfExprSyntax(
        ifKeyword: .keyword(.if, trailingTrivia: .space),
        conditions: ConditionElementListSyntax([
            ConditionElementSyntax(
                condition: .optionalBinding(
                    OptionalBindingConditionSyntax(
                        bindingSpecifier: .keyword(.let, trailingTrivia: .space),
                        pattern: IdentifierPatternSyntax(
                            identifier: .identifier("override", trailingTrivia: .space)
                        ),
                        initializer: InitializerClauseSyntax(
                            equal: .equalToken(trailingTrivia: .space),
                            value: DeclReferenceExprSyntax(
                                baseName: .identifier(overrideName, trailingTrivia: .space)
                            )
                        )
                    )
                )
            )
        ]),
        body: CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .space),
            statements: CodeBlockItemListSyntax([
                returnStmt(expr: ExprSyntax(
                    DeclReferenceExprSyntax(
                        baseName: .identifier("override", trailingTrivia: .space)
                    )
                ))
            ]),
            rightBrace: .rightBraceToken()
        )
    )
    return CodeBlockItemSyntax(
        item: .stmt(StmtSyntax(ExpressionStmtSyntax(expression: ExprSyntax(ifStmt))))
    )
}

/// Builds a `CodeBlockItemSyntax` containing a `fatalError("<message>")` call.
internal func fatalErrorStmt(message: String) -> CodeBlockItemSyntax {
    let call = FunctionCallExprSyntax(
        calledExpression: DeclReferenceExprSyntax(baseName: .identifier("fatalError")),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([
            LabeledExprSyntax(
                expression: ExprSyntax(StringLiteralExprSyntax(content: message))
            )
        ]),
        rightParen: .rightParenToken()
    )
    return CodeBlockItemSyntax(item: .expr(ExprSyntax(call)))
}

// MARK: - Deferred wrapper cycle-escape helpers

/// Local reference cell emitted inside macro-generated init bodies.
///
/// The class is local to the generated initializer so InnoDI does not expose a
/// public runtime helper just to support macro expansion in downstream
/// modules. Generated code mutates the cell during initialization, then only
/// resolves it through escaped `Lazy<T>` / `Provider<T>` closures.
///
/// ## Concurrency contract
///
/// `_InnoDIDeferredCell` is intentionally unsynchronized — the previous public
/// `_LazyCell` used `NSLock`, but the inlined cell is only ever stitched into
/// macro-emitted init bodies that observe a single, strict ordering:
///
/// 1. The cell is allocated and immediately captured by a closure passed to a
///    `Lazy<T>` / `Provider<T>` / sub-container builder during init.
/// 2. `storeValue(_:)` and `bindResolver(_:)` are called exactly once each
///    from the same init body, before init returns.
/// 3. After init returns, the macro guarantees the cell is read-only —
///    `resolve()` is the only operation invoked and it does not mutate state.
///
/// Concurrent `resolve()` calls are safe because both `value` and `resolver`
/// are written before any captured closure can escape (Swift's initialization
/// model serializes init-time writes with the implicit happens-before of the
/// init returning). Callers MUST NOT race `storeValue(_:)` /
/// `bindResolver(_:)` against `resolve()`; macro expansion is the only
/// supported producer of these calls and it never spawns concurrent work
/// inside init bodies. If you find yourself constructing this cell by hand,
/// add explicit synchronization.
internal func makeDeferredCellSupportDecl() -> DeclSyntax {
    """
    final class _InnoDIDeferredCell<T>: @unchecked Sendable {
        private var value: T?
        private var resolver: (() -> T)?

        func storeValue(_ value: T) {
            self.value = value
        }

        func bindResolver(_ resolver: @escaping () -> T) {
            self.resolver = resolver
        }

        func resolve() -> T {
            if let value {
                return value
            }
            if let resolver {
                return resolver()
            }
            fatalError("_InnoDIDeferredCell resolved before the dependency was initialized.")
        }
    }
    """
}

/// Builds a `let _lazyCell_<name> = _InnoDIDeferredCell<Type>()` local
/// binding used to implement the soft-edge (`Lazy<T>`) escape hatch. The
/// cell is captured as a heap-allocated box while the initializer runs, so
/// any `Lazy` wrapper distributed beforehand continues to share the same
/// reference after the target storage is populated. Because it is a `let`
/// binding, wrappers created after container-init can read the value safely
/// without any mutable capture.
internal func makeLazyCellDecl(name: String, type: TypeSyntax) -> DeclSyntax {
    makeDeferredCellDecl(cellName: "_lazyCell_\(name)", type: type)
}

/// Builds a `let <cellName> = _InnoDIDeferredCell<Type>()` local binding.
internal func makeDeferredCellDecl(cellName: String, type: TypeSyntax) -> DeclSyntax {
    let genericClause = GenericArgumentClauseSyntax(
        arguments: GenericArgumentListSyntax([
            GenericArgumentSyntax(argument: .type(type.trimmed))
        ])
    )
    let initCall = FunctionCallExprSyntax(
        calledExpression: ExprSyntax(
            GenericSpecializationExprSyntax(
                expression: DeclReferenceExprSyntax(baseName: .identifier("_InnoDIDeferredCell")),
                genericArgumentClause: genericClause
            )
        ),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([]),
        rightParen: .rightParenToken()
    )

    return letBinding(name: cellName, value: ExprSyntax(initCall))
}

/// Builds a write expression in the shape
/// `_lazyCell_<name>.storeValue(self._storage_<name>)`.
///
/// Called immediately after the init populates shared/input storage, so that
/// a `Lazy` wrapper distributed beforehand returns the same instance when it
/// finally resolves.
internal func makeLazyCellStoreExpr(name: String, storageName: String) -> ExprSyntax {
    let cellMember = MemberAccessExprSyntax(
        base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("_lazyCell_\(name)"))),
        declName: DeclReferenceExprSyntax(baseName: .identifier("storeValue"))
    )
    let call = FunctionCallExprSyntax(
        calledExpression: ExprSyntax(cellMember),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([
            LabeledExprSyntax(expression: makeSelfMemberAccessExpr(name: storageName))
        ]),
        rightParen: .rightParenToken()
    )
    return ExprSyntax(call)
}

/// Builds a late-binding expression in the shape
/// `_lazyCell_<name>.bindResolver { self.<name> }`.
///
/// A `.transient` soft target must recompute a fresh value through the
/// accessor after init, so the cell binds a resolver closure instead of
/// storing a concrete value.
internal func makeLazyCellBindExpr(name: String, accessorName: String, baseName: String = "self") -> ExprSyntax {
    let resolverAccess = MemberAccessExprSyntax(
        base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("_lazyCell_\(name)"))),
        declName: DeclReferenceExprSyntax(baseName: .identifier("bindResolver"))
    )
    let closure = ClosureExprSyntax(
        statements: CodeBlockItemListSyntax([
            CodeBlockItemSyntax(item: .expr(makeSelfMemberAccessExpr(name: accessorName, baseName: baseName)))
        ])
    )
    let call = FunctionCallExprSyntax(
        calledExpression: ExprSyntax(resolverAccess),
        leftParen: nil,
        arguments: LabeledExprListSyntax([]),
        rightParen: nil,
        trailingClosure: closure
    )
    return ExprSyntax(call)
}

/// Builds an argument expression in the shape
/// `<Qualified>.Lazy({ _lazyCell_<name>.resolve() })`.
///
/// Passed to a factory that declared a soft parameter. `Lazy`'s generic
/// parameter is inferred from the closure return type, so `<Type>` is
/// intentionally omitted.
internal func makeLazyCellWrapperExpr(name: String, calleeDescription: String) -> ExprSyntax {
    makeDeferredCellWrapperExpr(name: name, calleeDescription: calleeDescription)
}

/// Builds a `<Qualified>.Lazy({ self.<name> })` wrapper.
///
/// Used inside a transient accessor (getter). At getter time `self` is
/// already fully initialized, so storage can be read directly without an
/// init-time box.
internal func makeLazyAccessorWrapperExpr(
    name: String,
    calleeDescription: String
) -> ExprSyntax {
    makeDeferredAccessorWrapperExpr(
        name: name,
        calleeDescription: calleeDescription
    )
}

// MARK: - Provider wrappers
//
// A `Provider<T>` wrapper shares the same trailing-closure call shape as
// `Lazy<T>`, but resolves the target `.transient` storage afresh on every
// call. Codegen reuses the local `_InnoDIDeferredCell` infrastructure: the
// cell binds `{ self.<name> }` as its resolver, and every `resolve()` call
// runs that closure to produce a new instance. The wrapper therefore
// differs from `Lazy` only in which nominal type wraps the closure.

/// Builds an argument expression in the shape
/// `<Qualified>.Provider({ _lazyCell_<name>.resolve() })`. Injected into a
/// `Provider<T>` parameter on the `.shared` init path.
internal func makeProviderCellWrapperExpr(name: String, calleeDescription: String) -> ExprSyntax {
    makeDeferredCellWrapperExpr(name: name, calleeDescription: calleeDescription)
}

/// Builds a `<Qualified>.Provider({ self.<name> })` wrapper. Used inside
/// a transient accessor (`self` is already fully initialized at call time).
internal func makeProviderAccessorWrapperExpr(
    name: String,
    calleeDescription: String
) -> ExprSyntax {
    makeDeferredAccessorWrapperExpr(
        name: name,
        calleeDescription: calleeDescription
    )
}

/// Builds a deferred wrapper expression that resolves through the
/// `_lazyCell_<name>.resolve()` cell.
private func makeDeferredCellWrapperExpr(name: String, calleeDescription: String) -> ExprSyntax {
    makeLazyCellWrapperExprCore(name: name, calleeDescription: calleeDescription)
}

/// Builds a deferred wrapper expression that captures `self.<name>` directly.
///
/// This path is intentionally non-`Sendable`. Accessor-based `Lazy<T>` /
/// `Provider<T>` are only meant for use within the container's existing
/// isolation domain and do not support actor-boundary transport.
private func makeDeferredAccessorWrapperExpr(
    name: String,
    calleeDescription: String
) -> ExprSyntax {
    makeDeferredWrapperExpr(
        calleeDescription: calleeDescription,
        resolverExpression: makeSelfMemberAccessExpr(name: name)
    )
}

/// Shared implementation behind `makeDeferredCellWrapperExpr` so both `Lazy`
/// and `Provider` paths can reuse it. Callers pick the wrapper name
/// (`"Lazy"`, `"Provider"`, `"InnoDI.Lazy"`, …) via `calleeDescription`.
private func makeLazyCellWrapperExprCore(name: String, calleeDescription: String) -> ExprSyntax {
    let resolveAccess = MemberAccessExprSyntax(
        base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("_lazyCell_\(name)"))),
        declName: DeclReferenceExprSyntax(baseName: .identifier("resolve"))
    )
    let resolveCall = FunctionCallExprSyntax(
        calledExpression: ExprSyntax(resolveAccess),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([]),
        rightParen: .rightParenToken()
    )
    return makeDeferredWrapperExpr(calleeDescription: calleeDescription, resolverExpression: ExprSyntax(resolveCall))
}

private func makeDeferredWrapperExpr(calleeDescription: String, resolverExpression: ExprSyntax) -> ExprSyntax {
    let closure = ClosureExprSyntax(
        statements: CodeBlockItemListSyntax([
            CodeBlockItemSyntax(item: .expr(resolverExpression))
        ])
    )
    let call = FunctionCallExprSyntax(
        calledExpression: ExprSyntax("\(raw: calleeDescription)"),
        leftParen: nil,
        arguments: LabeledExprListSyntax([]),
        rightParen: nil,
        trailingClosure: closure
    )
    return ExprSyntax(call)
}

// MARK: - Task wrapper decl

/// Assembles the `DeclSyntax` for
/// `let <taskName> = Task<Success, Failure> { if let override = <overrideName> { return override }; return <awaitedFactoryExpr> }`
/// directly via the `SwiftSyntaxBuilder` AST.
internal func makeAsyncTaskDecl(
    taskName: String,
    overrideName: String,
    successType: String,
    failureType: String,
    awaitedFactoryExpr: ExprSyntax
) -> DeclSyntax {
    // Task<Success, Failure>
    let genericClause = GenericArgumentClauseSyntax(
        arguments: GenericArgumentListSyntax([
            GenericArgumentSyntax(
                argument: .type(TypeSyntax("\(raw: successType)")),
                trailingComma: .commaToken(trailingTrivia: .space)
            ),
            GenericArgumentSyntax(argument: .type(TypeSyntax("\(raw: failureType)")))
        ])
    )
    let taskRef = GenericSpecializationExprSyntax(
        expression: DeclReferenceExprSyntax(baseName: .identifier("Task")),
        genericArgumentClause: genericClause
    )

    // Task<...> { ... }
    let closure = ClosureExprSyntax(
        statements: CodeBlockItemListSyntax([
            overrideCheckStmt(overrideName: overrideName),
            returnStmt(expr: awaitedFactoryExpr)
        ])
    )
    let taskCall = FunctionCallExprSyntax(
        calledExpression: ExprSyntax(taskRef),
        leftParen: nil,
        arguments: LabeledExprListSyntax([]),
        rightParen: nil,
        trailingClosure: closure
    )

    return letBinding(name: taskName, value: ExprSyntax(taskCall))
}
