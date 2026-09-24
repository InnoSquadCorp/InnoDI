import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
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

/// InnoDI-managed identifiers become part of generated Swift symbol names and
/// graph lookup keys. Backtick spellings are valid Swift source, but preserving
/// the raw token would embed the backticks in synthesized names while stripping
/// them selectively would make expansion semantics depend on normalization.
/// InnoDI 6.0 therefore rejects these spellings at the declaration boundary.
func isEscapedInnoDIIdentifier(_ token: TokenSyntax) -> Bool {
    InnoDICore.isEscapedInnoDIIdentifier(token)
}

func unescapedInnoDIIdentifierName(_ token: TokenSyntax) -> String {
    InnoDICore.unescapedInnoDIIdentifierName(token)
}

extension DIContainerDeclarationSupport {
    func diagnose(
        at attribute: AttributeSyntax,
        declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) {
        switch self {
        case .supported:
            return
        case let .unsupportedKind(name, kind):
            context.emit(
                SimpleDiagnostic.containerUnsupportedDeclarationKind(
                    name: name,
                    kind: kind
                ),
                at: Syntax(attribute)
            )
        case let .privateAccess(name):
            let privateModifier = declaration.modifiers.first(where: {
                $0.name.text == "private"
            })
            let anchor = privateModifier.map(Syntax.init) ?? Syntax(attribute)
            var fixIts: [FixIt] = []
            // Only a bare `private` becomes `fileprivate` mechanically; a
            // detailed modifier such as `private(set)` needs a human call.
            if let privateModifier, privateModifier.detail == nil {
                fixIts.append(
                    makeTextReplacementFixIt(
                        replacing: privateModifier.name,
                        with: "fileprivate",
                        message: "Replace 'private' with 'fileprivate'",
                        code: .containerPrivateAccessUnsupported
                    )
                )
            }
            context.emit(
                SimpleDiagnostic.containerPrivateAccessUnsupported(
                    name: name
                ),
                at: anchor,
                fixIts: fixIts
            )
        case let .generic(name, contextName):
            context.emit(
                SimpleDiagnostic.containerGenericUnsupported(
                    name: name,
                    contextName: contextName
                ),
                at: Syntax(attribute)
            )
        case let .unverifiableEnclosingContext(name, extendedType):
            context.emit(
                SimpleDiagnostic.containerUnverifiableEnclosingContext(
                    name: name,
                    extendedType: extendedType
                ),
                at: Syntax(attribute)
            )
        case let .localDeclaration(name, localContext):
            context.emit(
                SimpleDiagnostic.containerLocalDeclarationUnsupported(
                    name: name,
                    context: localContext
                ),
                at: Syntax(attribute)
            )
        }
    }
}

/// Accessor macros must always emit a non-observing accessor. When InnoDI has
/// already rejected the declaration, this recovery getter keeps the compiler
/// from adding a second structural macro error. The primary diagnostic makes
/// the expansion unbuildable, so the body cannot reach runtime.
func failedDIValidationRecoveryAccessor(message _: String) -> AccessorDeclSyntax {
    let recoveryLoop: StmtSyntax = "while true {}"
    return AccessorDeclSyntax(
        accessorSpecifier: .keyword(.get),
        body: CodeBlockSyntax(
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(item: .stmt(recoveryLoop))
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
    guard InnoDICore.findDIContainerAttribute(in: declaration.attributes) != nil else {
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

/// Public `@Provide` is peer-only in InnoDI 6.0. A container attaches the
/// compiler-owned accessor only after this declaration shape has been proven
/// safe, which avoids Swift's structural accessor diagnostics for `let`,
/// computed, observed, and storage-modified declarations.
func isSupportedProvideStoredProperty(
    _ declaration: VariableDeclSyntax,
    allowingGeneratedMainActor: Bool = false
) -> Bool {
    InnoDICore.isSupportedProvideStoredProperty(
        declaration,
        allowingGeneratedMainActor: allowingGeneratedMainActor
    )
}

/// `@SubContainer` uses the same closed stored-instance boundary as provider
/// accessors, but allows only its cooperating public attributes. The hidden
/// accessor owner is attached after this source declaration has been proven
/// safe, so wrappers and unknown attributes cannot compete for storage.
func isSupportedSubContainerStoredProperty(
    _ declaration: VariableDeclSyntax
) -> Bool {
    InnoDICore.isSupportedSubContainerStoredProperty(declaration)
}

struct UnmanagedStoredContainerMember {
    let name: String
    let anchor: Syntax
}

/// Finds stored instance state that `@DIContainer` cannot initialize because
/// it is not owned by either `@Provide` or `@SubContainer`. InnoDI 6.0 emits an
/// explicit initializer even for a truly empty container so that every child
/// has a complete mount ABI; accepting unrelated stored state would therefore
/// remove the memberwise initializer and surface raw definite-initialization
/// errors. Computed and type properties remain available.
func unmanagedStoredContainerMembers(
    in declaration: some DeclGroupSyntax
) -> [UnmanagedStoredContainerMember] {
    var result: [UnmanagedStoredContainerMember] = []

    func appendUnmanagedBindings(from variable: VariableDeclSyntax) {
        guard InnoDICore.findManagedProviderAttribute(in: variable.attributes) == nil,
              findInnoDIAttribute(named: "SubContainer", in: variable.attributes) == nil,
              findInnoDIAttribute(named: "_InnoDIProvideAccessor", in: variable.attributes) == nil,
              findInnoDIAttribute(named: "_InnoDISubContainerAccessor", in: variable.attributes) == nil,
              !variable.modifiers.contains(where: {
                  $0.name.text == "static" || $0.name.text == "class"
              }) else {
            return
        }

        for binding in variable.bindings where isStoredContainerBinding(binding) {
            let anchor = Syntax(binding.pattern)
            result.append(
                UnmanagedStoredContainerMember(
                    name: binding.pattern.trimmedDescription,
                    anchor: anchor
                )
            )
        }
    }

    for member in declaration.memberBlock.members {
        if let variable = member.decl.as(VariableDeclSyntax.self) {
            appendUnmanagedBindings(from: variable)
            continue
        }
        guard let conditional = member.decl.as(IfConfigDeclSyntax.self) else {
            continue
        }
        collectConditionalUnmanagedStoredContainerMembers(
            in: Syntax(conditional),
            append: appendUnmanagedBindings
        )
    }
    return result
}

private func isStoredContainerBinding(_ binding: PatternBindingSyntax) -> Bool {
    guard let accessorBlock = binding.accessorBlock else {
        return true
    }
    switch accessorBlock.accessors {
    case .getter:
        return false
    case .accessors(let accessors):
        return !accessors.isEmpty && accessors.allSatisfy { accessor in
            accessor.accessorSpecifier.text == "willSet"
                || accessor.accessorSpecifier.text == "didSet"
        }
    }
}

private func collectConditionalUnmanagedStoredContainerMembers(
    in syntax: Syntax,
    append: (VariableDeclSyntax) -> Void
) {
    if let variable = syntax.as(VariableDeclSyntax.self) {
        append(variable)
        return
    }
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
        collectConditionalUnmanagedStoredContainerMembers(
            in: child,
            append: append
        )
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
    InnoDICore.canAttachGeneratedProvideAccessor(
        to: declaration,
        allowingGeneratedMainActor: allowingGeneratedMainActor
    )
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
    InnoDICore.isLocallyValidProvideConfiguration(
        declaration: declaration,
        arguments: arguments
    )
}

struct ConditionallyCompiledDIContainerMember {
    let declaration: VariableDeclSyntax
    let attribute: AttributeSyntax
    let attributeName: String
}

/// Returns direct container providers hidden inside a top-level conditional-
/// compilation block. Attached member macros do not receive these declarations
/// consistently across expansion roles: the container member phase can omit
/// them while the active declaration's peer/accessor phases still run. InnoDI
/// 5.0 therefore rejects the shape before any partial storage is generated.
func conditionallyCompiledProvideMembers(
    in declaration: some DeclGroupSyntax
) -> [ConditionallyCompiledDIContainerMember] {
    conditionallyCompiledDIContainerMembers(in: declaration).filter {
        $0.attributeName == "Provide"
            || $0.attributeName == "Input"
            || $0.attributeName == "SubContainerFactory"
            || $0.attributeName == "Multibinding"
    }
}

func conditionallyCompiledSubContainerMembers(
    in declaration: some DeclGroupSyntax
) -> [ConditionallyCompiledDIContainerMember] {
    conditionallyCompiledDIContainerMembers(in: declaration).filter {
        $0.attributeName == "SubContainer"
    }
}

private func conditionallyCompiledDIContainerMembers(
    in declaration: some DeclGroupSyntax
) -> [ConditionallyCompiledDIContainerMember] {
    var result: [ConditionallyCompiledDIContainerMember] = []
    for member in declaration.memberBlock.members {
        guard let conditional = member.decl.as(IfConfigDeclSyntax.self) else {
            continue
        }
        collectConditionallyCompiledDIContainerMembers(
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
        sameManagedDeclaration(declaration, candidate.declaration)
    }
}

func isConditionallyCompiledSubContainerMember(
    _ declaration: VariableDeclSyntax,
    in container: some DeclGroupSyntax
) -> Bool {
    conditionallyCompiledSubContainerMembers(in: container).contains { candidate in
        sameManagedDeclaration(declaration, candidate.declaration)
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
    return conditionallyCompiledDIContainerMembers(in: container).contains { candidate in
        sameManagedDeclaration(variable, candidate.declaration)
    }
}

private func collectConditionallyCompiledDIContainerMembers(
    in syntax: Syntax,
    into result: inout [ConditionallyCompiledDIContainerMember]
) {
    if let variable = syntax.as(VariableDeclSyntax.self) {
        for attributeName in [
            "Provide", "Input", "SubContainerFactory", "Multibinding",
            "SubContainer",
        ] {
            if let attribute = findInnoDIAttribute(
                named: attributeName,
                in: variable.attributes
            ) {
                result.append(
                    ConditionallyCompiledDIContainerMember(
                        declaration: variable,
                        attribute: attribute,
                        attributeName: attributeName
                    )
                )
            }
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
        collectConditionallyCompiledDIContainerMembers(in: child, into: &result)
    }
}

private func sameManagedDeclaration(
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
        guard InnoDICore.findDIContainerAttribute(
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
          InnoDICore.findDIContainerAttribute(
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

/// Returns true when the direct container owns a declaration that would
/// shadow generated storage or a compiler-authored module qualifier. Public
/// peer/accessor roles consult this before emitting partial support; the
/// container member role owns the stable diagnostics for every offending
/// declaration.
func directDIContainerHasReservedGeneratedName(
    _ declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
) -> Bool {
    if let container = directEnclosingDeclGroup(startingAt: Syntax(declaration)),
       InnoDICore.findDIContainerAttribute(in: container.attributes) != nil {
        return containerHasReservedGeneratedName(
            in: container,
            lexicalContext: context.lexicalContext
        )
    }

    for lexicalNode in context.lexicalContext {
        guard let container = diContainerDeclGroup(from: lexicalNode),
              InnoDICore.findDIContainerAttribute(
                in: container.attributes
              ) != nil else {
            continue
        }
        return containerHasReservedGeneratedName(
            in: container,
            lexicalContext: Array(context.lexicalContext.dropFirst())
        )
    }
    return false
}

/// For attached roles that must mirror the container's complete viability
/// gate without duplicating its user-facing diagnostics. The `@DIContainer`
/// member role remains the single diagnostic owner.
final class DiagnosticSuppressingMacroExpansionContext<
    Base: MacroExpansionContext
>: MacroExpansionContext {
    private let base: Base

    init(forwardingTo base: Base) {
        self.base = base
    }

    var lexicalContext: [Syntax] {
        base.lexicalContext
    }

    func makeUniqueName(_ name: String) -> TokenSyntax {
        base.makeUniqueName(name)
    }

    func diagnose(_ diagnostic: Diagnostic) {}

    func location(
        of node: some SyntaxProtocol,
        at position: PositionInSyntaxNode,
        filePathMode: SourceLocationFilePathMode
    ) -> AbstractSourceLocation? {
        base.location(
            of: node,
            at: position,
            filePathMode: filePathMode
        )
    }
}

/// Uses the same direct managed-member eligibility boundary as `DIContainerParser`
/// before deciding that two managed declarations compete for one identity.
/// The container member-attribute role calls this before attaching the hidden
/// storage/accessor owner, so its single recovery bit suppresses both roles.
func hasDuplicateManagedMemberName(
    _ member: VariableDeclSyntax,
    in declaration: some DeclGroupSyntax,
    options: DIContainerAttributeInfo
) -> Bool {
    guard isEligibleManagedMemberForDuplicateIdentity(
        member,
        options: options
    ), let memberName = member.bindings.first?
        .pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
        return false
    }

    var matchingCount = 0
    for sibling in declaration.memberBlock.members {
        guard let variable = sibling.decl.as(VariableDeclSyntax.self),
              isEligibleManagedMemberForDuplicateIdentity(
                  variable,
                  options: options
              ),
              variable.bindings.first?
                .pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                == memberName else {
            continue
        }
        matchingCount += 1
        if matchingCount > 1 {
            return true
        }
    }
    return false
}

private func isEligibleManagedMemberForDuplicateIdentity(
    _ variable: VariableDeclSyntax,
    options: DIContainerAttributeInfo
) -> Bool {
    guard let identifier = variable.bindings.first?
        .pattern.as(IdentifierPatternSyntax.self),
        !isEscapedInnoDIIdentifier(identifier.identifier) else {
        return false
    }

    let provideAttributes = InnoDICore.findManagedProviderAttributes(
        in: variable.attributes
    )
    let subContainerAttributes = findInnoDIAttributes(
        named: "SubContainer",
        in: variable.attributes
    )
    let hasExactlyOneManagedRole =
        (provideAttributes.count == 1 && subContainerAttributes.isEmpty)
        || (subContainerAttributes.count == 1 && provideAttributes.isEmpty)
    let hasSupportedShape = provideAttributes.count == 1
        ? isSupportedProvideStoredProperty(variable)
        : isSupportedSubContainerStoredProperty(variable)

    return hasExactlyOneManagedRole
        && !variable.modifiers.contains(where: {
            $0.name.text == "static" || $0.name.text == "class"
        })
        && (
            !options.mainActor
                || (
                    detectConflictingGlobalActor(in: variable.attributes) == nil
                        && !variable.modifiers.contains(where: {
                            $0.name.text == "nonisolated"
                        })
                )
        )
        && findInnoDIAttribute(
            named: "_InnoDIProvideAccessor",
            in: variable.attributes
        ) == nil
        && findInnoDIAttribute(
            named: "_InnoDISubContainerAccessor",
            in: variable.attributes
        ) == nil
        && hasSupportedShape
        && variable.bindings.first?.typeAnnotation != nil
        && variable.bindings.first?.pattern.is(IdentifierPatternSyntax.self) == true
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
           InnoDICore.findDIContainerAttribute(in: declaration.attributes) != nil {
            return declaration
        }
        current = node.parent
    }

    for node in lexicalContext {
        if let declaration = diContainerDeclGroup(from: node),
           InnoDICore.findDIContainerAttribute(in: declaration.attributes) != nil {
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
