//
//  ProvideMacro.swift
//  InnoDIMacros
//

import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct ProvideMacro: PeerMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingPeersOf decl: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let varDecl = decl.as(VariableDeclSyntax.self) else {
            return []
        }

        // Every public peer invocation sees the complete attribute list. Let
        // only the second @Provide own the global duplicate diagnostic so the
        // same contract also covers standalone and nested non-container uses.
        // All peer roles still suppress storage output.
        let provideAttributes = findInnoDIAttributes(
            named: "Provide",
            in: varDecl.attributes
        )
        guard provideAttributes.count == 1 else {
            if let diagnosticOwner = provideAttributes.dropFirst().first,
               hasSameSourceLocation(
                attribute,
                diagnosticOwner,
                in: context
               ) {
                let memberName = varDecl.bindings.first?
                    .pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                    ?? "<unknown>"
                context.diagnose(
                    Diagnostic(
                        node: Syntax(diagnosticOwner),
                        message: SimpleDiagnostic.provideDuplicateAttribute(
                            memberName: memberName
                        )
                    )
                )
            }
            return []
        }

        let membership = directDIContainerMembership(decl, in: context)
        if membership == .unsupported {
            // The enclosing @DIContainer declaration owns the single terminal
            // declaration-shape/context diagnostic.
            return []
        }

        let parseResult = parseProvideArguments(attribute)
        if parseResult.scope == nil {
            if let name = parseResult.scopeName {
                context.diagnose(
                    Diagnostic(
                        node: parseResult.scopeExpr.map(Syntax.init) ?? Syntax(attribute),
                        message: SimpleDiagnostic.provideUnknownScope(name)
                    )
                )
            }
            return []
        }

        if varDecl.bindings.count == 1,
           let identifier = varDecl.bindings.first?
            .pattern.as(IdentifierPatternSyntax.self)?.identifier,
           isEscapedInnoDIIdentifier(identifier) {
            context.diagnose(
                Diagnostic(
                    node: Syntax(identifier),
                    message: SimpleDiagnostic.provideEscapedPropertyIdentifier(
                        memberName: unescapedInnoDIIdentifierName(identifier)
                    )
                )
            )
            return []
        }

        let fallbackMemberName = varDecl.bindings.first?
            .pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            ?? "<unknown>"
        if membership == .none {
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic.provideRequiresDirectContainerMember(
                        memberName: fallbackMemberName
                    )
                )
            )
            return []
        }

        if let generatedAccessor = findInnoDIAttribute(
            named: "_InnoDIProvideAccessor",
            in: varDecl.attributes
        ), parseProvideAccessorRecovery(generatedAccessor) == true {
            // Trust recovery only after proving direct membership in a
            // supported container. A source-forged recovery accessor outside
            // a container must not suppress @Provide's public usage error.
            return []
        }

        // The container parser owns the more specific single-binding,
        // named-property, and explicit-type diagnostics for direct members.
        guard varDecl.bindings.count == 1,
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              binding.typeAnnotation != nil else {
            return []
        }

        if enclosingDIContainerInfo(for: decl, in: context)?.mainActor == true,
           detectConflictingGlobalActor(in: varDecl.attributes) != nil {
            // The container parser owns the dedicated actor-conflict
            // diagnostic. Unknown actor-like attributes still never receive a
            // generated accessor.
            return []
        }

        let hasContainerOwnedAccessor = findInnoDIAttribute(
            named: "_InnoDIProvideAccessor",
            in: varDecl.attributes
        ) != nil
        let allowsGeneratedMainActor = membership == .supported
            && hasContainerOwnedAccessor
            && enclosingDIContainerInfo(for: decl, in: context)?.mainActor == true
        guard isSupportedProvideStoredProperty(
            varDecl,
            allowingGeneratedMainActor: allowsGeneratedMainActor
        ) else {
            if hasContainerOwnedAccessor {
                // A source-forged support accessor is diagnosed by the
                // container member-attribute role. Do not add a second shape
                // diagnostic or collide with a source property wrapper.
                return []
            }
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic.provideRequiresDirectContainerMember(
                        memberName: identifier.identifier.text
                    )
                )
            )
            return []
        }

        // The container validator owns configuration diagnostics. Suppress
        // further peer work when the declaration is already invalid.
        guard isLocallyValidProvideConfiguration(
            declaration: varDecl,
            arguments: parseResult
        ) else {
            return []
        }

        // The compiler-owned support attribute attached by @DIContainer owns
        // both storage and accessors. Its peer role receives the same recovery
        // bit as its accessor role, so container-wide validation can suppress
        // both outputs without relying on public-peer expansion order.
        return []
    }
}

private func hasSameSourceLocation(
    _ lhs: AttributeSyntax,
    _ rhs: AttributeSyntax,
    in context: some MacroExpansionContext
) -> Bool {
    guard let lhsLocation = context.location(of: lhs),
          let rhsLocation = context.location(of: rhs) else {
        return Syntax(lhs).id == Syntax(rhs).id
    }

    return lhsLocation.file.trimmedDescription == rhsLocation.file.trimmedDescription
        && lhsLocation.line.trimmedDescription == rhsLocation.line.trimmedDescription
        && lhsLocation.column.trimmedDescription == rhsLocation.column.trimmedDescription
}

/// Owns storage and accessors for every validated direct `@Provide` member. Public
/// `@Provide` remains peer-only so unsupported `let` and computed declarations
/// can fail with one InnoDI diagnostic instead of Swift accessor-role errors.
/// The container member-attribute phase is the only phase that receives the
/// full sibling model, so it attaches this compiler-owned support macro after
/// declaration-shape validation and selects recovery once for both roles.
public struct InnoDIProvideAccessorMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard parseProvideAccessorRecovery(attribute) == false,
              let variable = declaration.as(VariableDeclSyntax.self),
              let binding = variable.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let type = binding.typeAnnotation?.type,
              let provideAttribute = findInnoDIAttribute(
                  named: "Provide",
                  in: variable.attributes
              ) else {
            return []
        }

        let isInstanceMember = !variable.modifiers.contains {
            $0.name.text == "static" || $0.name.text == "class"
        }
        guard isInstanceMember,
              directDIContainerMembership(declaration, in: context) == .supported else {
            return []
        }

        let parseResult = parseProvideArguments(provideAttribute)
        guard parseResult.scope != nil else { return [] }

        let isMainActor = enclosingDIContainerInfo(
            for: declaration,
            in: context
        )?.mainActor == true
        let allowsGeneratedMainActor = isMainActor
            && findStandardMainActorAttribute(in: variable.attributes) != nil
        guard canAttachGeneratedProvideAccessor(
            to: variable,
            allowingGeneratedMainActor: allowsGeneratedMainActor
        ), isLocallyValidProvideConfiguration(
            declaration: variable,
            arguments: parseResult
        ) else {
            return []
        }

        let memberName = identifier.identifier.text
        switch parseResult.scope {
        case .transient:
            return [
                providerStoragePeerDecl(
                    name: "_override_\(memberName)",
                    type: type
                )
            ]
        case .shared:
            if parseResult.asyncFactoryExpr != nil {
                return [
                    providerTaskStoragePeerDecl(
                        name: "_storage_task_\(memberName)",
                        successType: taskSuccessTypeDescription(for: type),
                        failureType: parseResult.asyncFactoryIsThrowing
                            ? "Error"
                            : "Never"
                    )
                ]
            }
            return [
                providerStoragePeerDecl(
                    name: "_storage_\(memberName)",
                    type: type
                )
            ]
        case .input:
            return [
                providerStoragePeerDecl(
                    name: "_storage_\(memberName)",
                    type: type
                )
            ]
        case .none:
            return []
        }
    }

    public static func expansion(
        of attribute: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self),
              let binding = variable.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic.provideGeneratedAccessorManualAttachment(
                        memberName: "<unknown>"
                    )
                )
            )
            return [
                failedDIValidationRecoveryAccessor(
                    message: "Invalid generated @Provide accessor owner"
                )
            ]
        }

        guard let provideAttribute = findInnoDIAttribute(
            named: "Provide",
            in: variable.attributes
        ) else {
            if isDirectMemberOfSupportedDIContainer(declaration, in: context) {
                // The enclosing member-attribute macro owns the single manual
                // attachment diagnostic for container members.
                return [
                    failedDIValidationRecoveryAccessor(
                        message: "Invalid generated @Provide accessor owner"
                    )
                ]
            }
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic.provideGeneratedAccessorManualAttachment(
                        memberName: identifier.identifier.text
                    )
                )
            )
            return [
                failedDIValidationRecoveryAccessor(
                    message: "Invalid generated @Provide accessor owner"
                )
            ]
        }

        let isInstanceMember = !variable.modifiers.contains {
            $0.name.text == "static" || $0.name.text == "class"
        }
        let membership = directDIContainerMembership(declaration, in: context)
        guard isInstanceMember, membership == .supported else {
            if membership == .none {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(attribute),
                        message: SimpleDiagnostic.provideGeneratedAccessorManualAttachment(
                            memberName: identifier.identifier.text
                        )
                    )
                )
            }
            return [
                failedDIValidationRecoveryAccessor(
                    message: "Invalid generated @Provide accessor owner"
                )
            ]
        }

        let parseResult = parseProvideArguments(provideAttribute)

        guard parseResult.scope != nil else {
            return [
                failedDIValidationRecoveryAccessor(
                    message: "Invalid generated @Provide accessor scope"
                )
            ]
        }

        // The container member-attribute phase owns the user-facing manual
        // attachment diagnostic. A nonliteral argument can only come from
        // source, because the generator below always emits a Bool literal.
        // Recover silently here to avoid a second internal-invariant error.
        guard let recovery = parseProvideAccessorRecovery(attribute) else {
            return [
                failedDIValidationRecoveryAccessor(
                    message: "Invalid generated @Provide accessor"
                )
            ]
        }

        if recovery {
            return [
                failedDIValidationRecoveryAccessor(
                    message: "Invalid @Provide dependency"
                )
            ]
        }

        let memberName = identifier.identifier.text
        let isMainActor = enclosingDIContainerInfo(
            for: declaration,
            in: context
        )?.mainActor == true
        let allowsGeneratedMainActor = isMainActor
            && findStandardMainActorAttribute(in: variable.attributes) != nil
        guard canAttachGeneratedProvideAccessor(
            to: variable,
            allowingGeneratedMainActor: allowsGeneratedMainActor
        ) else {
            return []
        }

        guard isLocallyValidProvideConfiguration(
            declaration: variable,
            arguments: parseResult
        ) else {
            return [
                failedDIValidationRecoveryAccessor(
                    message: "Invalid generated @Provide accessor configuration"
                )
            ]
        }

        switch parseResult.scope {
        case .shared:
            if parseResult.asyncFactoryExpr != nil {
                let storageName = "_storage_task_\(memberName)"
                let valueExpr = ExprSyntax(MemberAccessExprSyntax(
                    base: ForceUnwrapExprSyntax(
                        expression: DeclReferenceExprSyntax(
                            baseName: .identifier(storageName)
                        )
                    ),
                    declName: DeclReferenceExprSyntax(baseName: .identifier("value"))
                ))
                return isolateProvideAccessors([
                    makeGetter(
                        statements: [
                            awaitedReturnStmt(
                                expr: valueExpr,
                                isThrowing: parseResult.asyncFactoryIsThrowing
                            )
                        ],
                        isAsync: true,
                        isThrowing: parseResult.asyncFactoryIsThrowing
                    )
                ], isMainActor: isMainActor)
            }

            return isolateProvideAccessors(
                [storedProvideGetter(storageName: "_storage_\(memberName)")],
                isMainActor: isMainActor
            )

        case .input:
            return isolateProvideAccessors(
                [storedProvideGetter(storageName: "_storage_\(memberName)")],
                isMainActor: isMainActor
            )

        case .transient:
            return isolateProvideAccessors(makeTransientProvideAccessors(
                attribute: provideAttribute,
                declaration: declaration,
                binding: binding,
                memberName: memberName,
                parseResult: parseResult,
                enclosingContainerInfo: enclosingDIContainerInfo(
                    for: declaration,
                    in: context
                ),
                context: context
            ), isMainActor: isMainActor)

        case .none:
            return [
                failedDIValidationRecoveryAccessor(
                    message: "Invalid generated @Provide accessor scope"
                )
            ]
        }
    }
}

private func isolateProvideAccessors(
    _ accessors: [AccessorDeclSyntax],
    isMainActor: Bool
) -> [AccessorDeclSyntax] {
    guard isMainActor else { return accessors }
    return accessors.map { accessor in
        var isolated = accessor
        isolated.attributes = mainActorAttributeList()
        return isolated
    }
}

private func parseProvideAccessorRecovery(_ attribute: AttributeSyntax) -> Bool? {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
          let recoveryArgument = arguments.first(where: { $0.label?.text == "recovery" }) else {
        return nil
    }
    return InnoDICore.parseBoolArgument(recoveryArgument.expression).value
}

private func storedProvideGetter(storageName: String) -> AccessorDeclSyntax {
    makeGetter(
        statements: [
            returnStmt(
                expr: ExprSyntax(
                    ForceUnwrapExprSyntax(
                        expression: DeclReferenceExprSyntax(
                            baseName: .identifier(storageName)
                        )
                    )
                )
            )
        ],
        isAsync: false,
        isThrowing: false
    )
}

private func makeTransientProvideAccessors(
    attribute: AttributeSyntax,
    declaration: some DeclSyntaxProtocol,
    binding: PatternBindingSyntax,
    memberName: String,
    parseResult: ProvideArguments,
    enclosingContainerInfo: DIContainerAttributeInfo?,
    context: some MacroExpansionContext
) -> [AccessorDeclSyntax] {
    let overrideName = "_override_\(memberName)"

    // Site #1 in `docs/internal/fatalerror-inventory.md`. The validator phase
    // emits a terminal diagnostic for every input that reaches this branch.
    if let resolutionFailure = transientDependencyResolutionFailure(
        declaration: declaration,
        parseResult: parseResult,
        memberName: memberName
    ) {
        if enclosingContainerInfo?.validateDAG == false,
           let diagnostic = resolutionFailure.diagnostic(memberName: memberName) {
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: diagnostic
                )
            )
        }
        return []
    }

    let overrideCheck = overrideCheckStmt(overrideName: overrideName)

    if let asyncFactory = parseResult.asyncFactoryExpr {
        let createExpr: ExprSyntax

        if let closure = asyncFactory.as(ClosureExprSyntax.self) {
            let parsedArguments = parseClosureParameterNames(closure)
            if parsedArguments.hasWildcard {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(closure),
                        message: SimpleDiagnostic.transientFactoryUnnamedParameters()
                    )
                )
                return []
            }
            do {
                createExpr = try makeTransientClosureCallExpr(
                    closure: closure,
                    parsed: parsedArguments
                )
            } catch let error as CodegenInvariantError {
                return handleCodegenInvariant(
                    error,
                    attribute: attribute,
                    context: context
                )
            } catch {
                return handleCodegenInvariant(
                    CodegenInvariantError(
                        description: "Unexpected transient async factory lowering error: \(error)"
                    ),
                    attribute: attribute,
                    context: context
                )
            }
        } else {
            createExpr = asyncFactory
        }

        return [
            makeGetter(
                statements: [
                    overrideCheck,
                    awaitedReturnStmt(
                        expr: createExpr,
                        isThrowing: parseResult.asyncFactoryIsThrowing
                    )
                ],
                isAsync: true,
                isThrowing: parseResult.asyncFactoryIsThrowing
            )
        ]
    }

    let createExpr: ExprSyntax
    if let factory = parseResult.factoryExpr {
        if let closure = factory.as(ClosureExprSyntax.self) {
            let parsedArguments = parseClosureParameterNames(closure)
            if parsedArguments.hasWildcard {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(closure),
                        message: SimpleDiagnostic.transientFactoryUnnamedParameters()
                    )
                )
                return []
            }
            do {
                createExpr = try makeTransientClosureCallExpr(
                    closure: closure,
                    parsed: parsedArguments
                )
            } catch let error as CodegenInvariantError {
                return handleCodegenInvariant(
                    error,
                    attribute: attribute,
                    context: context
                )
            } catch {
                return handleCodegenInvariant(
                    CodegenInvariantError(
                        description: "Unexpected transient factory lowering error: \(error)"
                    ),
                    attribute: attribute,
                    context: context
                )
            }
        } else {
            createExpr = factory
        }
    } else if let typeExpr = parseResult.typeExpr {
        let arguments = parseResult.dependencies.map { dependency in
            LabeledExprSyntax(
                label: .identifier(dependency),
                colon: .colonToken(),
                expression: makeSelfMemberAccessExpr(name: dependency)
            )
        }
        createExpr = ExprSyntax(
            FunctionCallExprSyntax(
                calledExpression: typeExpr,
                leftParen: .leftParenToken(),
                arguments: LabeledExprListSyntax(arguments),
                rightParen: .rightParenToken()
            )
        )
    } else if let initializer = binding.initializer?.value {
        createExpr = initializer
    } else {
        context.diagnose(
            Diagnostic(
                node: Syntax(attribute),
                message: SimpleDiagnostic.provideTransientFactoryRequired()
            )
        )
        return []
    }

    return [
        makeGetter(
            statements: [
                overrideCheck,
                returnStmt(expr: createExpr)
            ],
            isAsync: false,
            isThrowing: false
        )
    ]
}

/// Site #6 in `docs/internal/fatalerror-inventory.md`. Internal codegen
/// invariants previously synthesized a `fatalError` getter as a "should
/// never happen" runtime trap. Phase 2.B downgrades it to a
/// diagnostic-only path so that an InnoDI invariant bug surfaces as a
/// build error rather than a release-time crash.
private func handleCodegenInvariant(
    _ error: CodegenInvariantError,
    attribute: AttributeSyntax,
    context: some MacroExpansionContext
) -> [AccessorDeclSyntax] {
    context.diagnose(
        Diagnostic(
            node: Syntax(attribute),
            message: SimpleDiagnostic.internalCodegenInvariant(description: error.description)
        )
    )
    return []
}

private func makeGetter(
    statements: [CodeBlockItemSyntax],
    isAsync: Bool,
    isThrowing: Bool
) -> AccessorDeclSyntax {
    AccessorDeclSyntax(
        accessorSpecifier: .keyword(.get),
        effectSpecifiers: makeAccessorEffectSpecifiers(isAsync: isAsync, isThrowing: isThrowing),
        body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(statements))
    )
}

private func makeAccessorEffectSpecifiers(
    isAsync: Bool,
    isThrowing: Bool
) -> AccessorEffectSpecifiersSyntax? {
    guard isAsync else { return nil }
    let throwsClause: ThrowsClauseSyntax? = isThrowing
        ? ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))
        : nil
    return AccessorEffectSpecifiersSyntax(
        asyncSpecifier: .keyword(.async),
        throwsClause: throwsClause
    )
}

private func enclosingDIContainerInfo(
    for declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
) -> DIContainerAttributeInfo? {
    for node in context.lexicalContext {
        if let structDecl = node.as(StructDeclSyntax.self),
           let info = parseDIContainerAttribute(structDecl.attributes) {
            return info
        }
        if let classDecl = node.as(ClassDeclSyntax.self),
           let info = parseDIContainerAttribute(classDecl.attributes) {
            return info
        }
        if let actorDecl = node.as(ActorDeclSyntax.self),
           let info = parseDIContainerAttribute(actorDecl.attributes) {
            return info
        }
    }

    var current: Syntax? = Syntax(declaration).parent

    while let node = current {
        if let structDecl = node.as(StructDeclSyntax.self),
           let info = parseDIContainerAttribute(structDecl.attributes) {
            return info
        }
        if let classDecl = node.as(ClassDeclSyntax.self),
           let info = parseDIContainerAttribute(classDecl.attributes) {
            return info
        }
        if let actorDecl = node.as(ActorDeclSyntax.self),
           let info = parseDIContainerAttribute(actorDecl.attributes) {
            return info
        }

        current = node.parent
    }

    return nil
}

private enum TransientDependencyResolutionFailure {
    case unresolvedWithDependency(String)
    case unresolvedFactoryParameter(String)
    case missingMember

    func diagnostic(memberName: String) -> SimpleDiagnostic? {
        switch self {
        case let .unresolvedWithDependency(dependency):
            return .provideUnresolvedWithDependency(
                memberName: memberName,
                dependencyName: dependency
            )
        case let .unresolvedFactoryParameter(parameter):
            return .provideUnresolvedFactoryParameter(
                memberName: memberName,
                parameterName: parameter
            )
        case .missingMember:
            return nil
        }
    }
}

private func transientDependencyResolutionFailure(
    declaration: some DeclSyntaxProtocol,
    parseResult: ProvideArguments,
    memberName: String
) -> TransientDependencyResolutionFailure? {
    guard let members = enclosingProvideMemberNames(for: declaration) else {
        return nil
    }

    let knownNames = Set(members)

    for dependency in parseResult.dependencies where !knownNames.contains(dependency) {
        return .unresolvedWithDependency(dependency)
    }

    let parameterNames: [String]
    if let closure = parseResult.factoryExpr?.as(ClosureExprSyntax.self) {
        parameterNames = parseClosureParameterNames(closure).names
    } else if let closure = parseResult.asyncFactoryExpr?.as(ClosureExprSyntax.self) {
        parameterNames = parseClosureParameterNames(closure).names
    } else {
        parameterNames = []
    }

    for dependency in parameterNames where !knownNames.contains(dependency) {
        return .unresolvedFactoryParameter(dependency)
    }

    if !knownNames.contains(memberName) {
        return .missingMember
    }

    return nil
}

private func enclosingProvideMemberNames(for declaration: some DeclSyntaxProtocol) -> [String]? {
    var current: Syntax? = Syntax(declaration).parent

    while let node = current {
        let declGroup: (any DeclGroupSyntax)?
        switch true {
        case node.is(StructDeclSyntax.self):
            declGroup = node.as(StructDeclSyntax.self)
        case node.is(ClassDeclSyntax.self):
            declGroup = node.as(ClassDeclSyntax.self)
        case node.is(ActorDeclSyntax.self):
            declGroup = node.as(ActorDeclSyntax.self)
        default:
            declGroup = nil
        }

        if let declGroup,
           parseDIContainerAttribute(declGroup.attributes) != nil {
            return declGroup.memberBlock.members.compactMap { member in
                guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                      hasProvideAttribute(varDecl.attributes),
                      let binding = varDecl.bindings.first,
                      let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                    return nil
                }
                return identifier.identifier.text
            }
        }

        current = node.parent
    }

    return nil
}

/// Builds the factory-call expression for a transient accessor. Same as
/// `makeClosureCallExpr(closure:argumentNames:)` except soft (Lazy<T>)
/// parameters are wrapped as `Lazy({ self.<name> })`, because the accessor
/// runs after `self` is fully initialized and therefore can capture it
/// directly — no init-time deferred cell plumbing is needed here.
private func makeTransientClosureCallExpr(
    closure: ClosureExprSyntax,
    parsed: ClosureParameterList
) throws -> ExprSyntax {
    // If the references list is available, honor soft kinds; otherwise fall
    // back to the plain member-access path.
    if parsed.references.isEmpty || parsed.references.allSatisfy({ $0.kind == .hard }) {
        return makeClosureCallExpr(closure: closure, argumentNames: parsed.names)
    }

    let expressions: [ExprSyntax] = try parsed.references.map { ref in
        if ref.kind == .soft {
            guard let calleeDescription = ref.lazyWrapperCalleeDescription else {
                throw CodegenInvariantError(description: "Soft transient dependency '\(ref.name)' is missing a Lazy wrapper callee.")
            }
            return makeLazyAccessorWrapperExpr(
                name: ref.name,
                calleeDescription: calleeDescription
            )
        }
        if ref.kind == .provider {
            guard let calleeDescription = ref.providerWrapperCalleeDescription else {
                throw CodegenInvariantError(description: "Provider transient dependency '\(ref.name)' is missing a Provider wrapper callee.")
            }
            return makeProviderAccessorWrapperExpr(
                name: ref.name,
                calleeDescription: calleeDescription
            )
        }
        return makeSelfMemberAccessExpr(name: ref.name)
    }
    return makeClosureCallExpr(closure: closure, argumentExpressions: expressions)
}

private func hasProvideAttribute(_ attributes: AttributeListSyntax?) -> Bool {
    findInnoDIAttribute(named: "Provide", in: attributes) != nil
}
