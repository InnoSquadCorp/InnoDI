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
        let provideAttributes = InnoDICore.findManagedProviderAttributes(
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
                context.emit(
                    SimpleDiagnostic.provideDuplicateAttribute(
                        memberName: memberName
                    ),
                    at: Syntax(diagnosticOwner),
                    fixIts: [
                        makeRemovalFixIt(
                            removing: diagnosticOwner,
                            message: "Remove the duplicate @Provide attribute",
                            code: .provideDuplicateAttribute
                        )
                    ]
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
                context.emit(
                    SimpleDiagnostic.provideUnknownScope(name),
                    at: parseResult.scopeExpr.map(Syntax.init) ?? Syntax(attribute)
                )
            }
            return []
        }
        if parseResult.initialization == nil {
            context.emit(
                SimpleDiagnostic.provideUnknownInitialization(
                    parseResult.initializationName ?? "<unknown>"
                ),
                at: parseResult.initializationExpr.map(Syntax.init)
                    ?? Syntax(attribute)
            )
            return []
        }
        if parseResult.operationalEffect == nil {
            context.emit(
                SimpleDiagnostic.provideUnknownEffect(
                    parseResult.operationalEffectName ?? "<unknown>"
                ),
                at: parseResult.operationalEffectExpr.map(Syntax.init)
                    ?? Syntax(attribute)
            )
            return []
        }

        if varDecl.bindings.count == 1,
           let identifier = varDecl.bindings.first?
            .pattern.as(IdentifierPatternSyntax.self)?.identifier,
           isEscapedInnoDIIdentifier(identifier) {
            context.emit(
                SimpleDiagnostic.provideEscapedPropertyIdentifier(
                    memberName: unescapedInnoDIIdentifierName(identifier)
                ),
                at: Syntax(identifier)
            )
            return []
        }

        let fallbackMemberName = varDecl.bindings.first?
            .pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            ?? "<unknown>"
        if membership == .none {
            context.emit(
                SimpleDiagnostic.provideRequiresDirectContainerMember(
                    memberName: fallbackMemberName
                ),
                at: Syntax(attribute)
            )
            return []
        }

        guard !directDIContainerHasReservedGeneratedName(decl, in: context) else {
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
            context.emit(
                SimpleDiagnostic.provideRequiresDirectContainerMember(
                    memberName: identifier.identifier.text
                ),
                at: Syntax(attribute)
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

        // Assisted factories need source-visible parameter types even when the
        // factory and its parent live in different files of one target. Emit a
        // generated alias next to each input so the factory does not repeat the
        // written input type.
        if matchesInnoDIAttribute(
            named: "Input",
            attributeName: attribute.attributeName
        ), let type = binding.typeAnnotation?.type {
            let memberName = identifier.identifier.text
            let access = varDecl.modifiers.first { modifier in
                ["public", "package", "internal", "fileprivate", "private"]
                    .contains(modifier.name.text)
            }?.name.text
            let accessPrefix = access.map { "\($0) " } ?? ""
            return [
                DeclSyntax(
                    "\(raw: accessPrefix)typealias _InnoDIInputType_\(raw: memberName) = \(type)"
                )
            ]
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
