import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

func findInnoDIAttributes(
    named name: String,
    in attributes: AttributeListSyntax?
) -> [AttributeSyntax] {
    guard let attributes else { return [] }
    return attributes.compactMap { element in
        guard let attribute = element.as(AttributeSyntax.self),
              InnoDICore.matchesInnoDIAttribute(
                named: name,
                attributeName: attribute.attributeName
              ) else {
            return nil
        }
        return attribute
    }
}

extension DIContainerDeclarationSupport {
    func diagnose(
        at attribute: AttributeSyntax,
        in context: some MacroExpansionContext
    ) {
        switch self {
        case .supported:
            return
        case let .unsupportedKind(name, kind):
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic.containerUnsupportedDeclarationKind(
                        name: name,
                        kind: kind
                    )
                )
            )
        case let .generic(name, contextName):
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic.containerGenericUnsupported(
                        name: name,
                        contextName: contextName
                    )
                )
            )
        case let .unverifiableEnclosingContext(name, extendedType):
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic.containerUnverifiableEnclosingContext(
                        name: name,
                        extendedType: extendedType
                    )
                )
            )
        case let .localDeclaration(name, localContext):
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic.containerLocalDeclarationUnsupported(
                        name: name,
                        context: localContext
                    )
                )
            )
        }
    }
}

/// Accessor macros must always emit a non-observing accessor. When InnoDI has
/// already rejected the declaration, this recovery getter keeps the compiler
/// from adding a second structural macro error. The primary diagnostic makes
/// the expansion unbuildable, so the body cannot reach runtime.
func failedDIValidationRecoveryAccessor(message: String) -> AccessorDeclSyntax {
    let failure = FunctionCallExprSyntax(
        calledExpression: MemberAccessExprSyntax(
            base: DeclReferenceExprSyntax(baseName: .identifier("Swift")),
            period: .periodToken(),
            declName: DeclReferenceExprSyntax(
                baseName: .identifier("preconditionFailure")
            )
        ),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([
            LabeledExprSyntax(
                expression: ExprSyntax(
                    StringLiteralExprSyntax(
                        content: message
                    )
                )
            )
        ]),
        rightParen: .rightParenToken()
    )
    return AccessorDeclSyntax(
        accessorSpecifier: .keyword(.get),
        body: CodeBlockSyntax(
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(item: .expr(ExprSyntax(failure)))
            ])
        )
    )
}

func unsupportedDIContainerRecoveryAccessor() -> AccessorDeclSyntax {
    failedDIValidationRecoveryAccessor(
        message: "Unsupported @DIContainer declaration"
    )
}

func isEnclosedByUnsupportedDIContainer(
    _ declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
) -> Bool {
    guard let container = enclosingDIContainerDeclaration(
        startingAt: Syntax(declaration),
        lexicalContext: context.lexicalContext
    ) else {
        return false
    }

    return !classifyDIContainerDeclaration(
        container,
        lexicalContext: context.lexicalContext
    ).isSupported
}

func isSupportedDIContainerDeclarationIfPresent(
    _ declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext
) -> Bool {
    guard findInnoDIAttribute(named: "DIContainer", in: declaration.attributes) != nil else {
        return true
    }

    return classifyDIContainerDeclaration(
        declaration,
        lexicalContext: context.lexicalContext
    ).isSupported
}

enum DirectDIContainerMembership: Equatable {
    case none
    case supported
    case unsupported
}

/// Public `@Provide` is peer-only in InnoDI 5.0. A container attaches the
/// compiler-owned accessor only after this declaration shape has been proven
/// safe, which avoids Swift's structural accessor diagnostics for `let`,
/// computed, observed, and storage-modified declarations.
func isSupportedProvideStoredProperty(
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

    // SwiftSyntax cannot resolve an arbitrary attribute's semantic role. Keep
    // the 5.0 declaration contract closed: allow only InnoDI's cooperating
    // property attributes, plus `MainActor` after the container macro itself
    // generated it. Source-written actor-looking attributes are rejected before
    // an accessor macro can collide with a property wrapper because syntax
    // macros cannot distinguish `Swift.MainActor` from a user-defined
    // `@propertyWrapper struct MainActor` at this phase.
    let supportedAttributeNames: Set<String> = [
        "DIFeatureRoot",
        "Provide",
        "SubContainer",
        "_InnoDIProvideAccessor",
    ]
    return declaration.attributes.allSatisfy { element in
        guard let attribute = element.as(AttributeSyntax.self) else {
            // An AttributeList `#if` can hide a storage-transforming wrapper.
            // Syntax macros cannot prove the active branch, so 5.0 rejects the
            // declaration instead of attaching an accessor optimistically.
            return false
        }
        if InnoDICore.matchesAttribute(
            named: "MainActor",
            attributeName: attribute.attributeName,
            allowingQualifiedModules: ["Swift"]
        ) {
            return allowingGeneratedMainActor
        }
        return supportedAttributeNames.contains { name in
            InnoDICore.matchesInnoDIAttribute(
                named: name,
                attributeName: attribute.attributeName
            )
        }
    }
}

/// Accessor-role macros additionally require a single named binding with an
/// explicit type. Keep this separate from storage-shape validation so the
/// container parser can still emit its specific single-binding, named-property,
/// or explicit-type diagnostic without Swift adding an accessor-role error.
func canAttachGeneratedProvideAccessor(
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

/// Returns whether one syntactically valid direct provider has a locally
/// coherent construction contract. Derived sibling-edge validation is handled
/// separately; this predicate only prevents peer/accessor generation from
/// amplifying a primary declaration/configuration diagnostic into Swift
/// storage or effect errors.
func isLocallyValidProvideConfiguration(
    declaration: VariableDeclSyntax,
    arguments: ProvideArguments
) -> Bool {
    guard let scope = arguments.scope,
          !arguments.concreteParseState.isInvalid,
          !arguments.escapingParseState.isInvalid,
          !arguments.dependenciesParseState.isInvalid,
          declaration.bindings.count == 1,
          let binding = declaration.bindings.first,
          binding.pattern.is(IdentifierPatternSyntax.self),
          let type = binding.typeAnnotation?.type,
          !isOpaqueSomeType(type),
          !isImplicitlyUnwrappedOptionalType(type) else {
        return false
    }

    let constructionSourceCount = [
        arguments.factoryExpr != nil,
        arguments.asyncFactoryExpr != nil,
        arguments.typeExpr != nil,
        binding.initializer != nil,
    ].filter { $0 }.count
    let hasConstructionSource = constructionSourceCount > 0

    if constructionSourceCount > 1 {
        return false
    }

    switch scope {
    case .input:
        guard !hasConstructionSource,
              (!arguments.escaping || supportsExplicitEscapingInput(type)),
              !arguments.dependenciesParseState.hasArgument else {
            return false
        }
    case .shared, .transient:
        guard !arguments.escaping else { return false }
        guard hasConstructionSource else { return false }
        if arguments.dependenciesParseState.hasArgument,
           arguments.typeExpr == nil {
            return false
        }
    }

    if let asyncFactory = arguments.asyncFactoryExpr,
       !isAsyncClosureExpression(asyncFactory) {
        return false
    }

    if let factory = arguments.factoryExpr,
       isAsyncClosureExpression(factory)
        || factoryExpressionContainsAwait(factory)
        || isThrowingClosureExpression(factory)
        || factoryExpressionContainsPlainTry(factory) {
        return false
    }

    let closure = arguments.factoryExpr?.as(ClosureExprSyntax.self)
        ?? arguments.asyncFactoryExpr?.as(ClosureExprSyntax.self)
    if let closure, parseClosureParameterNames(closure).hasWildcard {
        return false
    }

    if scope != .input,
       !arguments.concrete,
       requiresConcreteOptIn(type: type) {
        return false
    }

    return true
}

struct ConditionallyCompiledProvideMember {
    let declaration: VariableDeclSyntax
    let attribute: AttributeSyntax
}

/// Returns direct container providers hidden inside a top-level conditional-
/// compilation block. Attached member macros do not receive these declarations
/// consistently across expansion roles: the container member phase can omit
/// them while the active declaration's peer/accessor phases still run. InnoDI
/// 5.0 therefore rejects the shape before any partial storage is generated.
func conditionallyCompiledProvideMembers(
    in declaration: some DeclGroupSyntax
) -> [ConditionallyCompiledProvideMember] {
    var result: [ConditionallyCompiledProvideMember] = []
    for member in declaration.memberBlock.members {
        guard let conditional = member.decl.as(IfConfigDeclSyntax.self) else {
            continue
        }
        collectConditionallyCompiledProvideMembers(
            in: Syntax(conditional),
            into: &result
        )
    }
    return result
}

func isConditionallyCompiledProvideMember(
    _ declaration: VariableDeclSyntax,
    in container: some DeclGroupSyntax
) -> Bool {
    conditionallyCompiledProvideMembers(in: container).contains { candidate in
        sameProvideDeclaration(declaration, candidate.declaration)
    }
}

/// Expansion inputs supplied by the compiler may be detached from their source
/// tree, so ancestry is only the fast path. The fallback matches the declaration
/// against the enclosing container's original top-level `#if` blocks.
func isConditionallyCompiledDIContainerMember(
    _ declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
) -> Bool {
    guard let container = enclosingDIContainerDeclaration(
        startingAt: Syntax(declaration),
        lexicalContext: context.lexicalContext
    ) else {
        return false
    }

    var current = Syntax(declaration).parent
    while let node = current {
        if node.is(IfConfigDeclSyntax.self) || node.is(IfConfigClauseSyntax.self) {
            return true
        }
        if diContainerDeclGroup(from: node) != nil {
            break
        }
        current = node.parent
    }

    for node in context.lexicalContext {
        if node.is(IfConfigDeclSyntax.self) || node.is(IfConfigClauseSyntax.self) {
            return true
        }
        if diContainerDeclGroup(from: node) != nil {
            break
        }
    }

    guard let variable = declaration.as(VariableDeclSyntax.self) else {
        return false
    }
    return conditionallyCompiledProvideMembers(in: container).contains { candidate in
        sameProvideDeclaration(variable, candidate.declaration)
    }
}

private func collectConditionallyCompiledProvideMembers(
    in syntax: Syntax,
    into result: inout [ConditionallyCompiledProvideMember]
) {
    if let variable = syntax.as(VariableDeclSyntax.self) {
        if let attribute = findInnoDIAttribute(
            named: "Provide",
            in: variable.attributes
        ) {
            result.append(
                ConditionallyCompiledProvideMember(
                    declaration: variable,
                    attribute: attribute
                )
            )
        }
        return
    }

    // A top-level #if may contain an entire nested declaration. Providers in
    // that nested lexical scope are not members of the outer container.
    if syntax.is(StructDeclSyntax.self)
        || syntax.is(ClassDeclSyntax.self)
        || syntax.is(ActorDeclSyntax.self)
        || syntax.is(EnumDeclSyntax.self)
        || syntax.is(ProtocolDeclSyntax.self)
        || syntax.is(ExtensionDeclSyntax.self)
        || syntax.is(FunctionDeclSyntax.self)
        || syntax.is(InitializerDeclSyntax.self)
        || syntax.is(SubscriptDeclSyntax.self)
        || syntax.is(ClosureExprSyntax.self) {
        return
    }

    for child in syntax.children(viewMode: .sourceAccurate) {
        collectConditionallyCompiledProvideMembers(in: child, into: &result)
    }
}

private func sameProvideDeclaration(
    _ lhs: VariableDeclSyntax,
    _ rhs: VariableDeclSyntax
) -> Bool {
    let lhsPosition = lhs.positionAfterSkippingLeadingTrivia.utf8Offset
    let rhsPosition = rhs.positionAfterSkippingLeadingTrivia.utf8Offset
    if lhsPosition == rhsPosition {
        return true
    }

    let lhsName = lhs.bindings.first?
        .pattern.as(IdentifierPatternSyntax.self)?.identifier.text
    let rhsName = rhs.bindings.first?
        .pattern.as(IdentifierPatternSyntax.self)?.identifier.text
    return lhsName != nil
        && lhsName == rhsName
}

/// Classifies the nearest nominal declaration around an attached member. An
/// outer container does not make members of an intervening nested type or
/// executable scope container-managed.
func directDIContainerMembership(
    _ declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
) -> DirectDIContainerMembership {
    if isConditionallyCompiledDIContainerMember(declaration, in: context) {
        return .unsupported
    }

    if let container = directEnclosingDeclGroup(startingAt: Syntax(declaration)) {
        guard findInnoDIAttribute(
            named: "DIContainer",
            in: container.attributes
        ) != nil else {
            return .none
        }
        return classifyDIContainerDeclaration(
            container,
            lexicalContext: []
        ).isSupported ? .supported : .unsupported
    }

    // Compiler-provided declarations can be detached from their source tree.
    // Lexical context is ordered inner-to-outer; stop at the nearest nominal
    // declaration instead of accepting any outer `@DIContainer`.
    guard let nearestContext = context.lexicalContext.first,
          let container = diContainerDeclGroup(from: nearestContext),
          findInnoDIAttribute(
              named: "DIContainer",
              in: container.attributes
          ) != nil else {
        return .none
    }
    let outerLexicalContext = Array(context.lexicalContext.dropFirst())
    return classifyDIContainerDeclaration(
        container,
        lexicalContext: outerLexicalContext
    ).isSupported ? .supported : .unsupported
}

func isDirectMemberOfSupportedDIContainer(
    _ declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
) -> Bool {
    if case .supported = directDIContainerMembership(declaration, in: context) {
        return true
    }
    return false
}

private func directEnclosingDeclGroup(
    startingAt syntax: Syntax
) -> (any DeclGroupSyntax)? {
    var current = syntax.parent
    while let node = current {
        if let declaration = diContainerDeclGroup(from: node) {
            return declaration
        }

        // These are the transparent syntax wrappers between a direct nominal
        // member and its declaration. Encountering an executable-scope node
        // fails closed instead of accidentally accepting a farther ancestor.
        guard node.is(MemberBlockItemSyntax.self)
            || node.is(MemberBlockItemListSyntax.self)
            || node.is(MemberBlockSyntax.self) else {
            return nil
        }
        current = node.parent
    }
    return nil
}

private func enclosingDIContainerDeclaration(
    startingAt syntax: Syntax,
    lexicalContext: [Syntax]
) -> (any DeclGroupSyntax)? {
    var current: Syntax? = syntax.parent
    while let node = current {
        if let declaration = diContainerDeclGroup(from: node),
           findInnoDIAttribute(named: "DIContainer", in: declaration.attributes) != nil {
            return declaration
        }
        current = node.parent
    }

    for node in lexicalContext {
        if let declaration = diContainerDeclGroup(from: node),
           findInnoDIAttribute(named: "DIContainer", in: declaration.attributes) != nil {
            return declaration
        }
    }

    return nil
}

private func diContainerDeclGroup(from syntax: Syntax) -> (any DeclGroupSyntax)? {
    if let declaration = syntax.as(StructDeclSyntax.self) {
        return declaration
    }
    if let declaration = syntax.as(ClassDeclSyntax.self) {
        return declaration
    }
    if let declaration = syntax.as(ActorDeclSyntax.self) {
        return declaration
    }
    if let declaration = syntax.as(EnumDeclSyntax.self) {
        return declaration
    }
    if let declaration = syntax.as(ProtocolDeclSyntax.self) {
        return declaration
    }
    if let declaration = syntax.as(ExtensionDeclSyntax.self) {
        return declaration
    }
    return nil
}
