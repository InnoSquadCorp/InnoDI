import SwiftSyntax

/// Returns whether an InnoDI-managed identifier uses a backtick spelling.
///
/// Managed member names become generated Swift symbols and graph keys. Keep
/// this syntax-only boundary in Core so macro expansion and build preflight
/// make the same generation-viability decision.
package func isEscapedInnoDIIdentifier(_ token: TokenSyntax) -> Bool {
    let text = token.text
    return text.count >= 2 && text.first == "`" && text.last == "`"
}

package func unescapedInnoDIIdentifierName(_ token: TokenSyntax) -> String {
    guard isEscapedInnoDIIdentifier(token) else { return token.text }
    return String(token.text.dropFirst().dropLast())
}

/// Returns whether `@Provide` can safely receive InnoDI's generated accessor
/// owner. This deliberately stays syntax-only because attached macros cannot
/// resolve the semantic role of arbitrary attributes or type aliases.
package func isSupportedProvideStoredProperty(
    _ declaration: VariableDeclSyntax,
    allowingGeneratedMainActor: Bool = false
) -> Bool {
    guard declaration.bindingSpecifier.tokenKind == .keyword(.var),
          declaration.bindings.count == 1,
          declaration.bindings.first?.accessorBlock == nil else {
        return false
    }

    let unsupportedStorageModifiers: Set<String> = [
        "class",
        "lazy",
        "static",
        "unowned",
        "weak",
    ]
    guard !declaration.modifiers.contains(where: {
        unsupportedStorageModifiers.contains($0.name.text)
            || $0.detail?.detail.text == "set"
    }) else {
        return false
    }

    let supportedAttributeNames: Set<String> = [
        "Provide",
        "Input",
        "SubContainerFactory",
        "SubContainer",
        "_InnoDIProvideAccessor",
        "_InnoDISubContainerAccessor",
    ]
    return declaration.attributes.allSatisfy { element in
        guard let attribute = element.as(AttributeSyntax.self) else {
            return false
        }
        if matchesAttribute(
            named: "MainActor",
            attributeName: attribute.attributeName,
            allowingQualifiedModules: ["Swift"]
        ) {
            return allowingGeneratedMainActor
        }
        return supportedAttributeNames.contains { name in
            matchesInnoDIAttribute(
                named: name,
                attributeName: attribute.attributeName
            )
        }
    }
}

/// Returns whether `@SubContainer` can safely receive InnoDI's generated
/// accessor owner.
package func isSupportedSubContainerStoredProperty(
    _ declaration: VariableDeclSyntax
) -> Bool {
    guard declaration.bindingSpecifier.tokenKind == .keyword(.var),
          declaration.bindings.count == 1,
          declaration.bindings.first?.accessorBlock == nil else {
        return false
    }

    let unsupportedStorageModifiers: Set<String> = [
        "class",
        "lazy",
        "nonisolated",
        "static",
        "unowned",
        "weak",
    ]
    guard !declaration.modifiers.contains(where: {
        unsupportedStorageModifiers.contains($0.name.text)
            || $0.detail?.detail.text == "set"
    }) else {
        return false
    }

    let supportedAttributeNames: Set<String> = [
        "Provide",
        "Input",
        "SubContainerFactory",
        "SubContainer",
    ]
    return declaration.attributes.allSatisfy { element in
        guard let attribute = element.as(AttributeSyntax.self) else {
            return false
        }
        return supportedAttributeNames.contains { name in
            matchesInnoDIAttribute(
                named: name,
                attributeName: attribute.attributeName
            )
        }
    }
}

package func canAttachGeneratedProvideAccessor(
    to declaration: VariableDeclSyntax,
    allowingGeneratedMainActor: Bool = false
) -> Bool {
    guard isSupportedProvideStoredProperty(
        declaration,
        allowingGeneratedMainActor: allowingGeneratedMainActor
    ),
          let binding = declaration.bindings.first,
          binding.pattern.is(IdentifierPatternSyntax.self),
          let type = binding.typeAnnotation?.type,
          !isOpaqueSomeType(type),
          !isImplicitlyUnwrappedOptionalType(type) else {
        return false
    }
    return true
}

package func canAttachGeneratedSubContainerAccessor(
    to declaration: VariableDeclSyntax
) -> Bool {
    guard isSupportedSubContainerStoredProperty(declaration),
          let binding = declaration.bindings.first,
          let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
          !isEscapedInnoDIIdentifier(identifier.identifier),
          binding.typeAnnotation != nil else {
        return false
    }
    return true
}

/// Returns whether one direct provider has a locally coherent construction
/// contract. Sibling lookup, graph, actor, and generated-name validation stay
/// outside this predicate.
package func isLocallyValidProvideConfiguration(
    declaration: VariableDeclSyntax,
    arguments: ProvideArguments
) -> Bool {
    guard declaration.bindings.count == 1,
          let binding = declaration.bindings.first else {
        return false
    }
    return isLocallyValidProvideConstruction(
        binding: binding,
        scope: arguments.scope,
        factory: arguments.factoryExpr,
        asyncFactory: arguments.asyncFactoryExpr,
        typeExpression: arguments.typeExpr,
        escaping: arguments.escaping,
        escapingParseState: arguments.escapingParseState,
        withDependenciesParseState: arguments.dependenciesParseState
    )
}

/// Lower-level provider construction gate shared by the parsed macro model and
/// full-source qualifier preflight.
package func isLocallyValidProvideConstruction(
    binding: PatternBindingSyntax,
    scope: ProvideScope?,
    factory: ExprSyntax?,
    asyncFactory: ExprSyntax?,
    typeExpression: ExprSyntax?,
    escaping: Bool,
    escapingParseState: BoolArgumentParseState,
    withDependenciesParseState: KeyPathArrayArgumentParseState
) -> Bool {
    guard let scope,
          !escapingParseState.isInvalid,
          !withDependenciesParseState.isInvalid,
          let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
          !isEscapedInnoDIIdentifier(identifier.identifier),
          let type = binding.typeAnnotation?.type,
          !isOpaqueSomeType(type),
          !isImplicitlyUnwrappedOptionalType(type) else {
        return false
    }

    let constructionSourceCount = [
        factory != nil,
        asyncFactory != nil,
        typeExpression != nil,
        binding.initializer != nil,
    ].filter { $0 }.count

    guard constructionSourceCount <= 1 else { return false }

    switch scope {
    case .input:
        guard constructionSourceCount == 0,
              (!escaping || supportsExplicitEscapingInput(type)),
              !withDependenciesParseState.hasArgument else {
            return false
        }
    case .shared, .transient:
        guard !escaping, constructionSourceCount == 1 else {
            return false
        }
        if withDependenciesParseState.hasArgument,
           typeExpression == nil {
            return false
        }
    }

    if let asyncFactory,
       !isAsyncClosureExpression(asyncFactory) {
        return false
    }

    if let factory,
       isAsyncClosureExpression(factory)
        || factoryExpressionContainsAwait(factory)
        || isThrowingClosureExpression(factory)
        || factoryExpressionContainsPlainTry(factory) {
        return false
    }

    let closure = factory?.as(ClosureExprSyntax.self)
        ?? asyncFactory?.as(ClosureExprSyntax.self)
    return closure.map(hasValidManagedFactoryParameterNames) ?? true
}

/// Returns whether a child member can participate in concrete container code
/// generation after its local attribute arguments have been parsed.
package func isLocallyValidSubContainerConfiguration(
    _ arguments: SubContainerAttributeInfo
) -> Bool {
    guard arguments.scope != nil,
          !arguments.bindingsParseState.isInvalid else {
        return false
    }
    if case .invalid = arguments.sameNameWiring {
        return false
    }
    return !(arguments.hasWithDependencies
        && arguments.bindingsParseState.hasArgument)
}

package func isOpaqueSomeType(_ type: TypeSyntax) -> Bool {
    guard let someOrAny = normalizedProviderType(type).as(
        SomeOrAnyTypeSyntax.self
    ) else {
        return false
    }
    return someOrAny.someOrAnySpecifier.tokenKind == .keyword(.some)
}

package func isImplicitlyUnwrappedOptionalType(
    _ type: TypeSyntax
) -> Bool {
    type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
}

package func isDirectNonOptionalFunctionType(_ type: TypeSyntax) -> Bool {
    if type.is(FunctionTypeSyntax.self) {
        return true
    }
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return isDirectNonOptionalFunctionType(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let first = tuple.elements.first,
       first.firstName == nil,
       first.secondName == nil {
        return isDirectNonOptionalFunctionType(first.type)
    }
    return false
}

package func supportsExplicitEscapingInput(_ type: TypeSyntax) -> Bool {
    guard !isExplicitOptionalType(type) else { return false }

    if isDirectNonOptionalFunctionType(type) {
        return true
    }
    if type.is(IdentifierTypeSyntax.self) || type.is(MemberTypeSyntax.self) {
        return true
    }
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return supportsExplicitEscapingInput(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let first = tuple.elements.first,
       first.firstName == nil,
       first.secondName == nil {
        return supportsExplicitEscapingInput(first.type)
    }
    return false
}

package func isAsyncClosureExpression(_ expression: ExprSyntax) -> Bool {
    expression.as(ClosureExprSyntax.self)?
        .signature?.effectSpecifiers?.asyncSpecifier != nil
}

package func isThrowingClosureExpression(_ expression: ExprSyntax) -> Bool {
    expression.as(ClosureExprSyntax.self)?
        .signature?.effectSpecifiers?.throwsClause != nil
}

package func factoryExpressionContainsAwait(_ expression: ExprSyntax) -> Bool {
    let visitor = FactoryEffectVisitor(
        rootClosure: expression.as(ClosureExprSyntax.self)
    )
    visitor.walk(Syntax(expression))
    return visitor.containsAwait
}

package func factoryExpressionContainsPlainTry(
    _ expression: ExprSyntax
) -> Bool {
    let visitor = FactoryEffectVisitor(
        rootClosure: expression.as(ClosureExprSyntax.self)
    )
    visitor.walk(Syntax(expression))
    return visitor.containsPlainTry
}

private func hasValidManagedFactoryParameterNames(
    _ closure: ClosureExprSyntax
) -> Bool {
    guard let parameterClause = closure.signature?.parameterClause else {
        return true
    }

    let tokens: [TokenSyntax]
    switch parameterClause {
    case .simpleInput(let parameters):
        tokens = parameters.map(\.name)
    case .parameterClause(let clause):
        tokens = clause.parameters.map {
            $0.secondName ?? $0.firstName
        }
    }

    var names: Set<String> = []
    for token in tokens {
        guard token.text != "_",
              !isEscapedInnoDIIdentifier(token),
              names.insert(token.text).inserted else {
            return false
        }
    }
    return true
}

private func isExplicitOptionalType(_ type: TypeSyntax) -> Bool {
    if type.is(OptionalTypeSyntax.self)
        || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
        return true
    }
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return isExplicitOptionalType(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let first = tuple.elements.first,
       first.firstName == nil,
       first.secondName == nil {
        return isExplicitOptionalType(first.type)
    }
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return identifier.name.text == "Optional"
            && identifier.genericArgumentClause != nil
    }
    if let member = type.as(MemberTypeSyntax.self) {
        return member.baseType.as(IdentifierTypeSyntax.self)?.name.text
            == "Swift"
            && member.name.text == "Optional"
            && member.genericArgumentClause != nil
    }
    return false
}

private func normalizedProviderType(_ type: TypeSyntax) -> TypeSyntax {
    if let optional = type.as(OptionalTypeSyntax.self) {
        return normalizedProviderType(optional.wrappedType)
    }
    if let implicitlyUnwrapped = type.as(
        ImplicitlyUnwrappedOptionalTypeSyntax.self
    ) {
        return normalizedProviderType(implicitlyUnwrapped.wrappedType)
    }
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return normalizedProviderType(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let first = tuple.elements.first,
       first.firstName == nil,
       first.secondName == nil {
        return normalizedProviderType(first.type)
    }
    if let identifier = type.as(IdentifierTypeSyntax.self),
       identifier.name.text == "Optional",
       let wrapped = identifier.genericArgumentClause?
        .arguments.first?.argument.as(TypeSyntax.self) {
        return normalizedProviderType(wrapped)
    }
    return type
}

private final class FactoryEffectVisitor: SyntaxVisitor {
    let rootClosurePosition: AbsolutePosition?
    var containsAwait = false
    var containsPlainTry = false
    private var handledThrowDepth = 0
    private var catchClauseHandledAdjustments: [Bool] = []

    init(rootClosure: ClosureExprSyntax?) {
        self.rootClosurePosition = rootClosure?.position
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: AwaitExprSyntax) -> SyntaxVisitorContinueKind {
        containsAwait = true
        return .skipChildren
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark == nil && handledThrowDepth == 0 {
            containsPlainTry = true
        }
        return .visitChildren
    }

    override func visit(_ node: DoStmtSyntax) -> SyntaxVisitorContinueKind {
        if hasCatchAll(node.catchClauses) {
            handledThrowDepth += 1
        }
        return .visitChildren
    }

    override func visitPost(_ node: DoStmtSyntax) {
        if hasCatchAll(node.catchClauses) {
            handledThrowDepth -= 1
        }
    }

    override func visit(
        _ node: CatchClauseSyntax
    ) -> SyntaxVisitorContinueKind {
        let adjusted = handledThrowDepth > 0
        if adjusted {
            handledThrowDepth -= 1
        }
        catchClauseHandledAdjustments.append(adjusted)
        return .visitChildren
    }

    override func visitPost(_ node: CatchClauseSyntax) {
        let adjusted = catchClauseHandledAdjustments.removeLast()
        if adjusted {
            handledThrowDepth += 1
        }
    }

    override func visit(
        _ node: ClosureExprSyntax
    ) -> SyntaxVisitorContinueKind {
        if let rootClosurePosition,
           node.position == rootClosurePosition {
            return .visitChildren
        }
        return .skipChildren
    }

    override func visit(
        _ node: FunctionDeclSyntax
    ) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(
        _ node: InitializerDeclSyntax
    ) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(
        _ node: SubscriptDeclSyntax
    ) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
}

private func hasCatchAll(_ catchClauses: CatchClauseListSyntax) -> Bool {
    catchClauses.contains { $0.catchItems.isEmpty }
}
