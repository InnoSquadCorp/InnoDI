//
//  DIContainerSubContainerGenerator.swift
//  InnoDIMacros
//
//  Helpers that emit `@SubContainer`-specific init statements, shared-scope
//  `_storage_sub_<name>` assignment chains, transient `_innoDISubBuild_`
//  closure captures, and the Swift-side `if let` ladders that implement
//  direct-replacement / trailing-closure / default-build precedence inside
//  the parent `@DIContainer` init.
//
//  Keeping these out of the main generator file isolates sub-container
//  codegen behavior without changing any emitted code.
//

import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Sub-container init / build helpers

/// Emits the init-time statements for a single `@SubContainer` member:
///
/// - `.shared`: builds the child (or accepts the override replacement) once
///   and assigns `_storage_sub_<name>`. The direct replacement wins; the
///   `<name>Overrides` trailing-closure block is forwarded to the child's
///   own convenience init when present.
/// - `.transient`: only the override wedges are captured; actual construction
///   happens lazily inside the stored `_innoDISubBuild_<name>` closure on
///   every accessor read.
///
/// `autoWireParentMemberNames` is the ordered list of parent `@Provide`
/// member names (input/shared/transient) that the call site forwards by
/// default. When the user wrote `with: [\.a, \.b]` on the attribute, that
/// list replaces the default — Swift's compile-time label check surfaces
/// mismatches with the child's `.input` parameter names.
internal func makeSubContainerInitStatements(
    member: SubContainerMemberModel,
    autoWireParentMemberNames: [String]
) -> [CodeBlockItemSyntax] {
    let selectedArguments = resolvedSubContainerArguments(
        member: member,
        autoWireParentMemberNames: autoWireParentMemberNames
    )

    var stmts: [CodeBlockItemSyntax] = []

    switch member.scope {
    case .shared:
        let ifChain = subContainerSharedAssignmentExpr(
            member: member,
            selectedArguments: selectedArguments
        )
        stmts.append(CodeBlockItemSyntax(item: .stmt(StmtSyntax(ExpressionStmtSyntax(expression: ExprSyntax(ifChain))))))

    case .transient, .none:
        // `.none` should be unreachable — `DIContainerValidator` (M-5)
        // rejects `@SubContainer` without a scope — but we stay silent here
        // rather than force a crash during macro expansion.
        break
    }

    // Both scopes capture the override wedges so the Overrides builder has
    // something to inspect at runtime (used by child accessor / helper).
    stmts.append(
        CodeBlockItemSyntax(item: .expr(assignExpr(
            targetName: "_override_sub_\(member.name)",
            valueName: member.name
        )))
    )
    stmts.append(
        CodeBlockItemSyntax(item: .expr(assignExpr(
            targetName: "_override_sub_apply_\(member.name)",
            valueName: member.overrideClosureName
        )))
    )

    return stmts
}

/// Renders the `if let direct = override { ... } else if let apply = ... { ... } else { ... }`
/// three-branch storage assignment used for `.shared` sub-containers. Built
/// directly as SwiftSyntax so malformed child type spellings cannot crash a
/// string-reparse fallback during macro expansion.
private func subContainerSharedAssignmentExpr(
    member: SubContainerMemberModel,
    selectedArguments: [(childLabel: String, parentName: String)]
) -> IfExprSyntax {
    let storageName = "_storage_sub_\(member.name)"
    let overrideParam = member.name
    let applyParam = member.overrideClosureName
    let directAssignment = assignExprWithValue(
        targetName: storageName,
        value: ExprSyntax(
            DeclReferenceExprSyntax(baseName: .identifier("direct"))
        )
    )
    let applyAssignment = assignExprWithValue(
        targetName: storageName,
        value: subContainerInitializerExpr(
            childType: member.type,
            argumentMappings: selectedArguments,
            trailingOverrideExpression: ExprSyntax(
                DeclReferenceExprSyntax(baseName: .identifier("apply"))
            )
        )
    )
    let defaultAssignment = assignExprWithValue(
        targetName: storageName,
        value: subContainerInitializerExpr(
            childType: member.type,
            argumentMappings: selectedArguments
        )
    )
    let elseIfExpr = makeSubContainerOptionalBindingIfExpr(
        bindingName: "apply",
        sourceName: applyParam,
        assignment: applyAssignment,
        elseBody: .codeBlock(
            CodeBlockSyntax(
                statements: CodeBlockItemListSyntax([
                    CodeBlockItemSyntax(item: .expr(defaultAssignment))
                ])
            )
        )
    )

    return makeSubContainerOptionalBindingIfExpr(
        bindingName: "direct",
        sourceName: overrideParam,
        assignment: directAssignment,
        elseBody: .ifExpr(elseIfExpr)
    )
}

internal func subContainerInitializerExpr(
    childType: TypeSyntax,
    argumentMappings: [(childLabel: String, parentName: String)],
    trailingOverrideExpression: ExprSyntax? = nil,
    parentMemberBaseName: String = "self",
    parentMemberPrefix: String = "_storage_"
) -> ExprSyntax {
    let totalArgumentCount = argumentMappings.count + (trailingOverrideExpression == nil ? 0 : 1)
    var arguments: [LabeledExprSyntax] = argumentMappings.enumerated().map { index, mapping in
        let hasTrailingOverride = trailingOverrideExpression != nil
        let isLast = index == argumentMappings.count - 1 && !hasTrailingOverride
        return LabeledExprSyntax(
            label: .identifier(mapping.childLabel),
            colon: .colonToken(),
            expression: makeSelfMemberAccessExpr(
                name: "\(parentMemberPrefix)\(mapping.parentName)",
                baseName: parentMemberBaseName
            ),
            trailingComma: isLast || totalArgumentCount == 0 ? nil : .commaToken()
        )
    }

    if let trailingOverrideExpression {
        arguments.append(
            LabeledExprSyntax(
                label: nil,
                colon: nil,
                expression: trailingOverrideExpression,
                trailingComma: nil
            )
        )
    }

    let call = FunctionCallExprSyntax(
        calledExpression: ExprSyntax("\(childType.trimmed)"),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax(arguments),
        rightParen: .rightParenToken()
    )
    return ExprSyntax(call)
}

internal func resolvedSubContainerArguments(
    member: SubContainerMemberModel,
    autoWireParentMemberNames: [String]
) -> [(childLabel: String, parentName: String)] {
    if member.hasBindingsArgument {
        return member.explicitBindings.map { binding in
            (childLabel: binding.childInputName, parentName: binding.parentMemberName)
        }
    }

    let selectedNames = resolvedSubContainerParentNames(
        member: member,
        autoWireParentMemberNames: autoWireParentMemberNames
    )
    return selectedNames.map { name in
        (childLabel: name, parentName: name)
    }
}

internal func resolvedSubContainerParentNames(
    member: SubContainerMemberModel,
    autoWireParentMemberNames: [String]
) -> [String] {
    switch member.sameNameWiring {
    case let .parsed(_, dependencies):
        return dependencies
    case .invalid:
        // The validator emits the invalid diagnostic; fall back to an empty
        // subset so the generator does not synthesize against half-known
        // wiring.
        return []
    case .omitted:
        return autoWireParentMemberNames
    }
}

internal func canResolveImplicitSubContainerParentNames(
    member: SubContainerMemberModel,
    autoWireParentMemberNames: [String]
) -> Bool {
    // The macro only blesses implicit auto-wiring when the parent has at
    // most one `@Provide` candidate. With zero candidates the generated call
    // is `Child()`; with exactly one candidate the call is
    // `Child(<name>: self._storage_<name>)`.
    //
    // The single-candidate convenience can still produce a Swift compile
    // error (label mismatch) when the child does not declare an `.input`
    // named `<name>`. The macro deliberately does not duplicate that check
    // here because the child container's input list is not visible at
    // single-attribute expansion time. Build-support hierarchy validation
    // performs the cross-module match (see
    // `WorkspaceHierarchyValidation` and the `sub.unknown-child-input`
    // diagnostic). Users who hit the Swift-side error in single-module
    // builds should add `with: []` to call `Child()` explicitly, or
    // `bindings:` to remap to the child input that exists.
    return autoWireParentMemberNames.count <= 1
}

private func makeSubContainerOptionalBindingIfExpr(
    bindingName: String,
    sourceName: String,
    assignment: ExprSyntax,
    elseBody: IfExprSyntax.ElseBody
) -> IfExprSyntax {
    IfExprSyntax(
        ifKeyword: .keyword(.if, trailingTrivia: .space),
        conditions: ConditionElementListSyntax([
            ConditionElementSyntax(
                condition: .optionalBinding(
                    OptionalBindingConditionSyntax(
                        bindingSpecifier: .keyword(.let, trailingTrivia: .space),
                        pattern: IdentifierPatternSyntax(
                            identifier: .identifier(bindingName, trailingTrivia: .space)
                        ),
                        initializer: InitializerClauseSyntax(
                            equal: .equalToken(trailingTrivia: .space),
                            value: DeclReferenceExprSyntax(
                                baseName: .identifier(sourceName, trailingTrivia: .space)
                            )
                        )
                    )
                )
            )
        ]),
        body: CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .space),
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(item: .expr(assignment))
            ]),
            rightBrace: .rightBraceToken()
        ),
        elseKeyword: .keyword(.else, leadingTrivia: .space, trailingTrivia: .space),
        elseBody: elseBody
    )
}
