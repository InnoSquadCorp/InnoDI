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
        ? optionalParameterType(for: type)
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

/// Container-owned provider storage is default-initialized so a terminal macro
/// diagnostic cannot create a second Swift definite-initialization or private
/// memberwise-init error. Valid generated container initializers always replace
/// `nil` before any public accessor can run.
internal func providerStoragePeerDecl(
    name: String,
    type: TypeSyntax
) -> DeclSyntax {
    let storedType = optionalParameterType(for: type)
    let decl = VariableDeclSyntax(
        modifiers: DeclModifierListSyntax([
            DeclModifierSyntax(name: .keyword(.private, trailingTrivia: .space))
        ]),
        bindingSpecifier: .keyword(.var, trailingTrivia: .space),
        bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier(name)),
                typeAnnotation: TypeAnnotationSyntax(
                    colon: .colonToken(trailingTrivia: .space),
                    type: storedType
                ),
                initializer: InitializerClauseSyntax(
                    equal: .equalToken(leadingTrivia: .space, trailingTrivia: .space),
                    value: NilLiteralExprSyntax()
                )
            )
        ])
    )
    return DeclSyntax(decl)
}

internal func providerOnDemandStoragePeerDecl(
    name: String,
    type: TypeSyntax
) -> DeclSyntax {
    let storedType = TypeSyntax(
        stringLiteral: "InnoDI._InnoDISharedCell<\(type.trimmedDescription)>?"
    )
    let decl = VariableDeclSyntax(
        modifiers: DeclModifierListSyntax([
            DeclModifierSyntax(name: .keyword(.private, trailingTrivia: .space))
        ]),
        bindingSpecifier: .keyword(.var, trailingTrivia: .space),
        bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier(name)),
                typeAnnotation: TypeAnnotationSyntax(
                    colon: .colonToken(trailingTrivia: .space),
                    type: storedType
                ),
                initializer: InitializerClauseSyntax(
                    equal: .equalToken(leadingTrivia: .space, trailingTrivia: .space),
                    value: NilLiteralExprSyntax()
                )
            )
        ])
    )
    return DeclSyntax(decl)
}

/// Builds the standard-library task type without allowing a nested container
/// declaration named `Task`, `Error`, or `Never` to shadow compiler-authored
/// async storage.
private func standardTaskType(
    successType: String,
    failureType: String
) -> TypeSyntax {
    let qualifiedFailureType: String
    switch failureType {
    case "Error":
        qualifiedFailureType = "Swift.Error"
    case "Never":
        qualifiedFailureType = "Swift.Never"
    default:
        qualifiedFailureType = failureType
    }
    return TypeSyntax(
        stringLiteral: "_Concurrency.Task<\(successType), \(qualifiedFailureType)>"
    )
}

/// Async counterpart of `providerStoragePeerDecl`.
internal func providerTaskStoragePeerDecl(
    name: String,
    successType: String,
    failureType: String
) -> DeclSyntax {
    let taskType = TypeSyntax(
        OptionalTypeSyntax(
            wrappedType: standardTaskType(
                successType: successType,
                failureType: failureType
            )
        )
    )
    let decl = VariableDeclSyntax(
        modifiers: DeclModifierListSyntax([
            DeclModifierSyntax(name: .keyword(.private, trailingTrivia: .space))
        ]),
        bindingSpecifier: .keyword(.var, trailingTrivia: .space),
        bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier(name)),
                typeAnnotation: TypeAnnotationSyntax(
                    colon: .colonToken(trailingTrivia: .space),
                    type: taskType
                ),
                initializer: InitializerClauseSyntax(
                    equal: .equalToken(leadingTrivia: .space, trailingTrivia: .space),
                    value: NilLiteralExprSyntax()
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
                        attributeName: TypeSyntax(
                            stringLiteral: "_Concurrency.MainActor "
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
        final class _InnoDIDeferredCell<T>: @unchecked Swift.Sendable {
            private var value: T?
            private var resolver: (() -> T)?

            func storeValue(_ value: T) {
                self.value = value
            }

            func bindResolver(_ resolver: @escaping () -> T) {
                self.resolver = resolver
            }

            func resolve() -> T {
                guard let value else {
                    if let resolver {
                        return resolver()
                    }
                    return InnoDI._innoDITrap("InnoDI codegen invariant violated: deferred dependency resolved before initialization completed.")
                }
                return value
            }
        }
    """
}

/// Builds a `let _innoDILazyCell_<name> = _InnoDIDeferredCell<Type>()` local
/// binding used to implement the soft-edge (`Lazy<T>`) escape hatch. The
/// cell is captured as a heap-allocated box while the initializer runs, so
/// any `Lazy` wrapper distributed beforehand continues to share the same
/// reference after the target storage is populated. Because it is a `let`
/// binding, wrappers created after container-init can read the value safely
/// without any mutable capture.
internal func makeLazyCellDecl(name: String, type: TypeSyntax) -> DeclSyntax {
    makeDeferredCellDecl(cellName: "_innoDILazyCell_\(name)", type: type)
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
/// `_innoDILazyCell_<name>.storeValue(self._storage_<name>)`.
///
/// Called immediately after the init populates shared/input storage, so that
/// a `Lazy` wrapper distributed beforehand returns the same instance when it
/// finally resolves.
internal func makeLazyCellStoreExpr(name: String, storageName: String) -> ExprSyntax {
    let cellMember = MemberAccessExprSyntax(
        base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("_innoDILazyCell_\(name)"))),
        declName: DeclReferenceExprSyntax(baseName: .identifier("storeValue"))
    )
    let call = FunctionCallExprSyntax(
        calledExpression: ExprSyntax(cellMember),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([
            LabeledExprSyntax(expression: makeProviderStorageReadExpr(name: storageName))
        ]),
        rightParen: .rightParenToken()
    )
    return ExprSyntax(call)
}

/// Builds a late-binding expression in the shape
/// `_innoDILazyCell_<name>.bindResolver { self.<name> }`.
///
/// A `.transient` soft target must recompute a fresh value through the
/// accessor after init, so the cell binds a resolver closure instead of
/// storing a concrete value.
internal func makeLazyCellBindExpr(name: String, accessorName: String, baseName: String = "self") -> ExprSyntax {
    let resolverAccess = MemberAccessExprSyntax(
        base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("_innoDILazyCell_\(name)"))),
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
/// `.init({ _innoDILazyCell_<name>.resolve() })`.
///
/// The factory parameter supplies the `Lazy<T>` contextual type, avoiding an
/// unqualified constructor name that a container member could shadow.
internal func makeLazyCellWrapperExpr(name: String, calleeDescription _: String) -> ExprSyntax {
    makeDeferredCellWrapperExpr(name: name)
}

/// Builds a contextual `.init({ self.<name> })` Lazy wrapper.
///
/// Used inside a transient accessor (getter). At getter time `self` is
/// already fully initialized, so storage can be read directly without an
/// init-time box.
internal func makeLazyAccessorWrapperExpr(
    name: String,
    calleeDescription _: String
) -> ExprSyntax {
    makeDeferredAccessorWrapperExpr(
        name: name
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

/// Builds a contextual `.init({ _innoDILazyCell_<name>.resolve() })` argument
/// for a `Provider<T>` parameter on the `.shared` init path.
internal func makeProviderCellWrapperExpr(name: String, calleeDescription _: String) -> ExprSyntax {
    makeDeferredCellWrapperExpr(name: name)
}

/// Builds a contextual `.init({ self.<name> })` Provider wrapper. Used inside a
/// transient accessor (`self` is already fully initialized at call time).
internal func makeProviderAccessorWrapperExpr(
    name: String,
    calleeDescription _: String
) -> ExprSyntax {
    makeDeferredAccessorWrapperExpr(
        name: name
    )
}

/// Builds a deferred wrapper expression that resolves through the
/// `_innoDILazyCell_<name>.resolve()` cell.
private func makeDeferredCellWrapperExpr(name: String) -> ExprSyntax {
    makeLazyCellWrapperExprCore(name: name)
}

/// Builds a deferred wrapper expression that captures `self.<name>` directly.
///
/// This path is intentionally non-`Sendable`. Accessor-based `Lazy<T>` /
/// `Provider<T>` are only meant for use within the container's existing
/// isolation domain and do not support actor-boundary transport.
private func makeDeferredAccessorWrapperExpr(
    name: String
) -> ExprSyntax {
    makeDeferredWrapperExpr(
        resolverExpression: makeSelfMemberAccessExpr(name: name)
    )
}

/// Shared implementation behind `makeDeferredCellWrapperExpr` so both `Lazy`
/// and `Provider` paths can reuse contextual `.init` construction without an
/// unqualified wrapper type name that a container member could shadow.
private func makeLazyCellWrapperExprCore(name: String) -> ExprSyntax {
    let resolveAccess = MemberAccessExprSyntax(
        base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("_innoDILazyCell_\(name)"))),
        declName: DeclReferenceExprSyntax(baseName: .identifier("resolve"))
    )
    let resolveCall = FunctionCallExprSyntax(
        calledExpression: ExprSyntax(resolveAccess),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([]),
        rightParen: .rightParenToken()
    )
    return makeDeferredWrapperExpr(resolverExpression: ExprSyntax(resolveCall))
}

private func makeDeferredWrapperExpr(resolverExpression: ExprSyntax) -> ExprSyntax {
    let closure = ClosureExprSyntax(
        statements: CodeBlockItemListSyntax([
            CodeBlockItemSyntax(item: .expr(resolverExpression))
        ])
    )
    let call = FunctionCallExprSyntax(
        calledExpression: MemberAccessExprSyntax(name: .keyword(.`init`)),
        leftParen: nil,
        arguments: LabeledExprListSyntax([]),
        rightParen: nil,
        trailingClosure: closure
    )
    return ExprSyntax(call)
}

// MARK: - Task wrapper decl

/// Assembles the `DeclSyntax` for
/// `let <taskName>: _Concurrency.Task<Success, Failure> = .init { if let override = <overrideName> { return override }; return <awaitedFactoryExpr> }`
/// directly via the `SwiftSyntaxBuilder` AST.
internal func makeAsyncTaskDecl(
    taskName: String,
    overrideName: String,
    successType: String,
    failureType: String,
    awaitedFactoryExpr: ExprSyntax
) -> DeclSyntax {
    let taskType = standardTaskType(
        successType: successType,
        failureType: failureType
    )

    // .init { ... }
    let closure = ClosureExprSyntax(
        statements: CodeBlockItemListSyntax([
            overrideCheckStmt(overrideName: overrideName),
            returnStmt(expr: awaitedFactoryExpr)
        ])
    )
    let taskCall = FunctionCallExprSyntax(
        calledExpression: MemberAccessExprSyntax(name: .keyword(.`init`)),
        leftParen: nil,
        arguments: LabeledExprListSyntax([]),
        rightParen: nil,
        trailingClosure: closure
    )

    return DeclSyntax(
        VariableDeclSyntax(
            bindingSpecifier: .keyword(.let, trailingTrivia: .space),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(taskName)),
                    typeAnnotation: TypeAnnotationSyntax(
                        colon: .colonToken(trailingTrivia: .space),
                        type: taskType
                    ),
                    initializer: InitializerClauseSyntax(
                        equal: .equalToken(leadingTrivia: .space, trailingTrivia: .space),
                        value: taskCall
                    )
                )
            ])
        )
    )
}
