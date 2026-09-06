//
//  ProvideAccessorMacro.swift
//  InnoDIMacros
//

import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

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
              let provideAttribute = InnoDICore.findManagedProviderAttribute(
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
        let memberName = unescapedInnoDIIdentifierName(identifier.identifier)
        guard memberName != "InnoDI",
              !reservedGeneratedMemberPrefixes.contains(where: {
                  memberName.hasPrefix($0)
              }),
              !directDIContainerHasReservedGeneratedName(
                  declaration,
                  in: context
              ) else {
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

        switch parseResult.scope {
        case .transient:
            return [
                providerTraceOwnerPeerDecl(name: memberName),
                providerStoragePeerDecl(
                    name: "_override_\(memberName)",
                    type: type
                )
            ]
        case .shared:
            if parseResult.asyncFactoryExpr != nil {
                return [
                    providerTraceOwnerPeerDecl(name: memberName),
                    providerTaskStoragePeerDecl(
                        name: "_storage_task_\(memberName)",
                        successType: taskSuccessTypeDescription(for: type),
                        failureType: parseResult.asyncFactoryIsThrowing
                            ? "Error"
                            : "Never"
                    )
                ]
            }
            if parseResult.initialization == .onDemand {
                return [
                    providerOnDemandStoragePeerDecl(
                        name: "_storage_\(memberName)",
                        type: type
                    )
                ]
            }
            return [
                providerTraceOwnerPeerDecl(name: memberName),
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
            context.emit(
                SimpleDiagnostic.provideGeneratedAccessorManualAttachment(
                    memberName: "<unknown>"
                ),
                at: Syntax(attribute)
            )
            return [
                failedDIValidationRecoveryAccessor(
                    message: "Invalid generated @Provide accessor owner"
                )
            ]
        }

        if directDIContainerHasReservedGeneratedName(declaration, in: context) {
            return [
                failedDIValidationRecoveryAccessor(
                    message: "Invalid reserved generated container name"
                )
            ]
        }
        let memberName = unescapedInnoDIIdentifierName(identifier.identifier)
        if memberName == "InnoDI"
            || reservedGeneratedMemberPrefixes.contains(where: {
                memberName.hasPrefix($0)
            }) {
            return [
                failedDIValidationRecoveryAccessor(
                    message: "Invalid reserved generated provider name"
                )
            ]
        }

        guard let provideAttribute = InnoDICore.findManagedProviderAttribute(
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
            context.emit(
                SimpleDiagnostic.provideGeneratedAccessorManualAttachment(
                    memberName: identifier.identifier.text
                ),
                at: Syntax(attribute)
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
                context.emit(
                    SimpleDiagnostic.provideGeneratedAccessorManualAttachment(
                        memberName: identifier.identifier.text
                    ),
                    at: Syntax(attribute)
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
                            parseResult.asyncFactoryIsThrowing
                                ? "let value = try await \(valueExpr)"
                                : "let value = await \(valueExpr)",
                            "self._innoDITraceOwner_\(raw: memberName).cacheHit(member: \"\(raw: memberName)\")",
                            "return value"
                        ],
                        isAsync: true,
                        isThrowing: parseResult.asyncFactoryIsThrowing
                    )
                ], isMainActor: isMainActor)
            }

            if parseResult.initialization == .onDemand {
                return isolateProvideAccessors(
                    [onDemandProvideGetter(storageName: "_storage_\(memberName)")],
                    isMainActor: isMainActor
                )
            }

            return isolateProvideAccessors(
                [storedProvideGetter(
                    storageName: "_storage_\(memberName)",
                    providerName: memberName,
                    tracesCacheHit: true
                )],
                isMainActor: isMainActor
            )

        case .input:
            return isolateProvideAccessors(
                [storedProvideGetter(
                    storageName: "_storage_\(memberName)",
                    providerName: memberName,
                    tracesCacheHit: false
                )],
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

private func onDemandProvideGetter(storageName: String) -> AccessorDeclSyntax {
    let expression: ExprSyntax = "self.\(raw: storageName)!.value()"
    return makeGetter(
        statements: [returnStmt(expr: expression)],
        isAsync: false,
        isThrowing: false
    )
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

func parseProvideAccessorRecovery(_ attribute: AttributeSyntax) -> Bool? {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
          let recoveryArgument = arguments.first(where: { $0.label?.text == "recovery" }) else {
        return nil
    }
    return InnoDICore.parseBoolArgument(recoveryArgument.expression).value
}

private func storedProvideGetter(
    storageName: String,
    providerName: String,
    tracesCacheHit: Bool
) -> AccessorDeclSyntax {
    var statements: [CodeBlockItemSyntax] = []
    if tracesCacheHit {
        statements.append(
            "self._innoDITraceOwner_\(raw: providerName).cacheHit(member: \"\(raw: providerName)\")"
        )
    }
    statements.append(
        returnStmt(
            expr: ExprSyntax(
                ForceUnwrapExprSyntax(
                    expression: DeclReferenceExprSyntax(
                        baseName: .identifier(storageName)
                    )
                )
            )
        )
    )
    return makeGetter(
        statements: statements,
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
            context.emit(
                diagnostic,
                at: Syntax(attribute)
            )
        }
        return []
    }

    let overrideCheck: CodeBlockItemSyntax = """
        if let override = self.\(raw: overrideName) {
            return self._innoDITraceOwner_\(raw: memberName).overridden(
                member: "\(raw: memberName)",
                value: override
            )
        }
        """

    if parseResult.isMultibinding {
        let elements = parseResult.dependencies.map {
            "self.\($0)"
        }.joined(separator: ", ")
        let collection: ExprSyntax = "[\(raw: elements)]"
        return [
            makeGetter(
                statements: [
                    overrideCheck,
                    """
                    return self._innoDITraceOwner_\(raw: memberName).withResolution(
                        member: "\(raw: memberName)"
                    ) {
                        \(collection)
                    }
                    """,
                ],
                isAsync: false,
                isThrowing: false
            )
        ]
    }

    if let asyncFactory = parseResult.asyncFactoryExpr {
        let createExpr: ExprSyntax

        if let closure = asyncFactory.as(ClosureExprSyntax.self) {
            let parsedArguments = parseClosureParameterNames(closure)
            if parsedArguments.hasWildcard {
                context.emit(
                    SimpleDiagnostic.transientFactoryUnnamedParameters(),
                    at: Syntax(closure)
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
                    parseResult.asyncFactoryIsThrowing
                        ? """
                          return try await self._innoDITraceOwner_\(raw: memberName).withResolution(
                              member: "\(raw: memberName)"
                          ) {
                              try await \(createExpr)
                          }
                          """
                        : """
                          return await self._innoDITraceOwner_\(raw: memberName).withResolution(
                              member: "\(raw: memberName)"
                          ) {
                              await \(createExpr)
                          }
                          """
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
                context.emit(
                    SimpleDiagnostic.transientFactoryUnnamedParameters(),
                    at: Syntax(closure)
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
        context.emit(
            SimpleDiagnostic.provideTransientFactoryRequired(),
            at: Syntax(attribute)
        )
        return []
    }

    return [
        makeGetter(
            statements: [
                overrideCheck,
                """
                return self._innoDITraceOwner_\(raw: memberName).withResolution(
                    member: "\(raw: memberName)"
                ) {
                    \(createExpr)
                }
                """
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
    context.emit(
        SimpleDiagnostic.internalCodegenInvariant(description: error.description),
        at: Syntax(attribute)
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

func enclosingDIContainerInfo(
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

enum TransientDependencyResolutionFailure {
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

func transientDependencyResolutionFailure(
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
    InnoDICore.findManagedProviderAttribute(in: attributes) != nil
}
