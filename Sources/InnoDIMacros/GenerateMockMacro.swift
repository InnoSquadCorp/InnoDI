//
//  GenerateMockMacro.swift
//  InnoDIMacros
//
//  RFC 0001 (`@GenerateMock`) experimental implementation.
//
//  Stage 1 (skeleton) shipped attribute validation and a tracking note.
//  Stage 2 (this file) walks a protocol's member block and emits a
//  call-recording mock peer for method and property requirements. Function
//  overloads get selector-qualified helper names, and generic methods use
//  erased handler closures so type parameters do not leak into type-scope
//  storage. Protocol-associated types remain unsupported until RFC 0001
//  settles the pinning model.
//

import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct GenerateMockMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: SimpleDiagnostic.generateMockRequiresProtocol()
                )
            )
            return []
        }

        let mockTypeName = "\(protocolDecl.name.text)Mock"
        var bodyLines: [String] = []
        var unsupportedMembers: [String] = []
        var usesNotStubbedError = false
        if protocolDecl.memberBlock.members.isEmpty {
            // Empty protocol — emit the skeleton note so consumers can still
            // confirm the macro plugin sees the attribute.
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: SimpleDiagnostic.generateMockExperimentalSkeleton(
                        protocolName: protocolDecl.name.text
                    )
                )
            )
        }

        let overloadCounts = Dictionary(
            grouping: protocolDecl.memberBlock.members.compactMap { member in
                member.decl.as(FunctionDeclSyntax.self)?.name.text
            },
            by: { $0 }
        ).mapValues(\.count)

        for member in protocolDecl.memberBlock.members {
            if let function = member.decl.as(FunctionDeclSyntax.self) {
                if let rendered = renderFunctionMock(
                    function: function,
                    isOverloaded: (overloadCounts[function.name.text] ?? 0) > 1
                ) {
                    bodyLines.append(rendered.snippet)
                    usesNotStubbedError = usesNotStubbedError || rendered.usesNotStubbedError
                } else {
                    unsupportedMembers.append(function.name.text)
                }
            } else if let variable = member.decl.as(VariableDeclSyntax.self) {
                if let snippet = renderVariableMock(variable: variable) {
                    bodyLines.append(snippet)
                } else {
                    unsupportedMembers.append(
                        variable.bindings.first?.pattern.trimmedDescription ?? "<unknown>"
                    )
                }
            } else {
                unsupportedMembers.append(unsupportedMemberName(member.decl))
            }
        }

        if !unsupportedMembers.isEmpty {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: SimpleDiagnostic.generateMockUnsupportedMember(
                        memberNames: unsupportedMembers
                    )
                )
            )
            // Do not synthesize a partial mock that still conforms to the
            // protocol; that would turn a scoped warning into a compiler error
            // at the generated conformance site.
            return []
        }

        if usesNotStubbedError {
            bodyLines.insert(
                """
                    struct _InnoDIMockNotStubbed: Error, CustomStringConvertible {
                        let selector: String
                        var description: String { "InnoDI mock selector '\\(selector)' was not stubbed before invocation." }
                    }
                """,
                at: 0
            )
        }

        let bodyJoined = bodyLines.joined(separator: "\n\n")
        let renderedBody: String
        if bodyJoined.isEmpty {
            renderedBody = "    // RFC 0001: no supported members yet — replace with the protocol's full member set."
        } else {
            renderedBody = bodyJoined
        }

        let mockDecl: DeclSyntax = """
        /// Auto-generated mock for `\(raw: protocolDecl.name.text)` (RFC 0001 stage 2).
        final class \(raw: mockTypeName): \(raw: protocolDecl.name.text), @unchecked Sendable {
            init() {}

        \(raw: renderedBody)
        }
        """
        return [mockDecl]
    }
}

private struct RenderedFunctionMock {
    let snippet: String
    let usesNotStubbedError: Bool
}

private struct MockFunctionNames {
    let stem: String
    let callStructName: String
    let callsProperty: String
    let returnProperty: String
    let resultProperty: String
    let thrownErrorProperty: String
    let handlerProperty: String
}

private func renderFunctionMock(
    function: FunctionDeclSyntax,
    isOverloaded: Bool
) -> RenderedFunctionMock? {
    if hasAnyModifier(function.modifiers, named: ["static", "class"]) {
        return nil
    }
    let isGeneric = function.genericParameterClause != nil
    if isGeneric {
        return renderGenericFunctionMock(function: function, forceQualifiedNames: isOverloaded)
    }
    return renderTypedFunctionMock(function: function, forceQualifiedNames: isOverloaded)
}

private func renderTypedFunctionMock(
    function: FunctionDeclSyntax,
    forceQualifiedNames: Bool
) -> RenderedFunctionMock? {
    let signature = function.signature
    let isAsync = signature.effectSpecifiers?.asyncSpecifier != nil
    let isThrowing = signature.effectSpecifiers?.throwsClause != nil

    let baseName = function.name.text
    let parameters = signature.parameterClause.parameters
    let callParameters = renderableCallParameters(parameters)

    let returnsVoid: Bool
    if let returnClause = signature.returnClause {
        returnsVoid = returnClause.type.trimmedDescription == "Void"
    } else {
        returnsVoid = true
    }

    let returnTypeRendered = signature.returnClause?.type.trimmedDescription ?? "Void"
    let parametersRendered = parameters.map { $0.trimmedDescription }.joined(separator: ", ")
    let names = makeFunctionNames(
        baseName: baseName,
        parameters: parameters,
        forceQualifiedNames: forceQualifiedNames
    )

    var effectSpecifierTokens: [String] = []
    if isAsync { effectSpecifierTokens.append("async") }
    if isThrowing { effectSpecifierTokens.append("throws") }
    let effectSpecifiersJoined = effectSpecifierTokens.isEmpty
        ? ""
        : " " + effectSpecifierTokens.joined(separator: " ")

    var snippetLines: [String] = []

    let callFields = callParameters
        .map { "        let \($0.name): \($0.type)" }
        .joined(separator: "\n")
    snippetLines.append("    struct \(names.callStructName) {")
    if !callFields.isEmpty {
        snippetLines.append(callFields)
    }
    snippetLines.append("    }")
    snippetLines.append("    private(set) var \(names.callsProperty): [\(names.callStructName)] = []")

    if !returnsVoid {
        if isThrowing {
            // `Result<T, Error>` keeps the typed `throw` lossy but lets the
            // mock author choose between `.success(value)` and `.failure(error)`
            // with a single assignment. The default failure prompts the test
            // author with the missing stub identifier through the nested
            // `_InnoDIMockNotStubbed` error.
            snippetLines.append(
                "    var \(names.resultProperty): Result<\(returnTypeRendered), Error> = .failure(_InnoDIMockNotStubbed(selector: \"\(baseName)\"))"
            )
        } else {
            snippetLines.append("    var \(names.returnProperty): \(returnTypeRendered)?")
        }
    } else if isThrowing {
        // Even a Void-returning throwing function needs an opt-in error
        // hook so tests can simulate the failure path.
        snippetLines.append("    var \(names.thrownErrorProperty): Error?")
    }

    let recordArgs = callParameters
        .map { "\($0.name): \($0.name)" }
        .joined(separator: ", ")
    let returnFragment = returnsVoid ? "" : " -> \(returnTypeRendered)"
    snippetLines.append("    func \(baseName)(\(parametersRendered))\(effectSpecifiersJoined)\(returnFragment) {")
    snippetLines.append("        \(names.callsProperty).append(.init(\(recordArgs)))")
    if !returnsVoid {
        if isThrowing {
            snippetLines.append("        return try \(names.resultProperty).get()")
        } else {
            snippetLines.append("        guard let value = \(names.returnProperty) else {")
            snippetLines.append("            preconditionFailure(\"\(names.returnProperty) was not set on \\(Swift.type(of: self)) before \(baseName) was invoked\")")
            snippetLines.append("        }")
            snippetLines.append("        return value")
        }
    } else if isThrowing {
        snippetLines.append("        if let error = \(names.thrownErrorProperty) {")
        snippetLines.append("            throw error")
        snippetLines.append("        }")
    }
    snippetLines.append("    }")

    return RenderedFunctionMock(
        snippet: snippetLines.joined(separator: "\n"),
        usesNotStubbedError: isThrowing && !returnsVoid
    )
}

private func renderGenericFunctionMock(
    function: FunctionDeclSyntax,
    forceQualifiedNames: Bool
) -> RenderedFunctionMock? {
    let signature = function.signature
    let isAsync = signature.effectSpecifiers?.asyncSpecifier != nil
    let isThrowing = signature.effectSpecifiers?.throwsClause != nil

    let baseName = function.name.text
    let parameters = signature.parameterClause.parameters
    let callParameters = renderableCallParameters(parameters, eraseTypes: true)
    let parametersRendered = parameters.map { $0.trimmedDescription }.joined(separator: ", ")
    let returnTypeRendered = signature.returnClause?.type.trimmedDescription ?? "Void"
    let returnsVoid = signature.returnClause?.type.trimmedDescription == nil
        || signature.returnClause?.type.trimmedDescription == "Void"
    let names = makeFunctionNames(
        baseName: baseName,
        parameters: parameters,
        forceQualifiedNames: true
    )

    var effectSpecifierTokens: [String] = []
    if isAsync { effectSpecifierTokens.append("async") }
    if isThrowing { effectSpecifierTokens.append("throws") }
    let effectSpecifiersJoined = effectSpecifierTokens.isEmpty
        ? ""
        : " " + effectSpecifierTokens.joined(separator: " ")

    let genericParameterClause = function.genericParameterClause?.trimmedDescription ?? ""
    let genericWhereClause = function.genericWhereClause.map { " " + $0.trimmedDescription } ?? ""
    let handlerEffectsJoined = effectSpecifiersJoined
    let handlerReturnType = returnsVoid ? "Void" : "Any"
    let invocationPrefix = effectInvocationPrefix(isAsync: isAsync, isThrowing: isThrowing)
    let handlerArguments = callParameters.map(\.name).joined(separator: ", ")
    let handlerArgumentArray = handlerArguments.isEmpty ? "[]" : "[\(handlerArguments)]"

    var snippetLines: [String] = []
    let callFields = callParameters
        .map { "        let \($0.name): \($0.type)" }
        .joined(separator: "\n")
    snippetLines.append("    struct \(names.callStructName) {")
    if !callFields.isEmpty {
        snippetLines.append(callFields)
    }
    snippetLines.append("    }")
    snippetLines.append("    private(set) var \(names.callsProperty): [\(names.callStructName)] = []")
    snippetLines.append("    var \(names.handlerProperty): (([Any])\(handlerEffectsJoined) -> \(handlerReturnType))?")

    let returnFragment = returnsVoid ? "" : " -> \(returnTypeRendered)"
    snippetLines.append("    func \(baseName)\(genericParameterClause)(\(parametersRendered))\(effectSpecifiersJoined)\(returnFragment)\(genericWhereClause) {")
    let recordArgs = callParameters.map { "\($0.name): \($0.name)" }.joined(separator: ", ")
    snippetLines.append("        \(names.callsProperty).append(.init(\(recordArgs)))")
    if returnsVoid {
        snippetLines.append("        if let handler = \(names.handlerProperty) {")
        snippetLines.append("            \(invocationPrefix)handler(\(handlerArgumentArray))")
        snippetLines.append("        }")
    } else {
        snippetLines.append("        guard let handler = \(names.handlerProperty) else {")
        snippetLines.append("            preconditionFailure(\"\(names.handlerProperty) was not set on \\(Swift.type(of: self)) before \(baseName) was invoked\")")
        snippetLines.append("        }")
        snippetLines.append("        let rawValue = \(invocationPrefix)handler(\(handlerArgumentArray))")
        snippetLines.append("        guard let value = rawValue as? \(returnTypeRendered) else {")
        snippetLines.append("            preconditionFailure(\"\(names.handlerProperty) returned a value that cannot be cast to \(returnTypeRendered)\")")
        snippetLines.append("        }")
        snippetLines.append("        return value")
    }
    snippetLines.append("    }")

    return RenderedFunctionMock(
        snippet: snippetLines.joined(separator: "\n"),
        usesNotStubbedError: false
    )
}

private func renderVariableMock(variable: VariableDeclSyntax) -> String? {
    guard variable.bindings.count == 1,
          let binding = variable.bindings.first,
          let typeAnnotation = binding.typeAnnotation,
          binding.pattern.is(IdentifierPatternSyntax.self) else {
        return nil
    }
    // Skip computed-only requirements with effects (async/throws getters).
    if let accessorBlock = binding.accessorBlock,
       case .accessors(let accessors) = accessorBlock.accessors {
        for accessor in accessors {
            if accessor.effectSpecifiers?.asyncSpecifier != nil { return nil }
            if accessor.effectSpecifiers?.throwsClause != nil { return nil }
        }
    }
    let name = (binding.pattern.as(IdentifierPatternSyntax.self))?.identifier.text ?? "<unknown>"
    let type = typeAnnotation.type.trimmedDescription
    // Implicit-unwrapped optional storage so the synthesized mock has a
    // valid `init()`; tests must populate the property before it is read.
    return "    var \(name): \(type)!"
}

private func renderableCallParameters(
    _ parameters: FunctionParameterListSyntax,
    eraseTypes: Bool = false
) -> [(name: String, type: String)] {
    var usedNames: [String: Int] = [:]
    return parameters.enumerated().map { index, parameter in
        let internalName = (parameter.secondName?.text ?? parameter.firstName.text)
        let baseFieldName = internalName == "_"
            ? "value\(index + 1)"
            : internalName.safeLowerCamelIdentifier
        let count = usedNames[baseFieldName, default: 0]
        usedNames[baseFieldName] = count + 1
        let fieldName = count == 0 ? baseFieldName : "\(baseFieldName)\(count + 1)"
        let typeText = eraseTypes ? "Any" : parameter.type.trimmedDescription
        return (fieldName, typeText)
    }
}

private func makeFunctionNames(
    baseName: String,
    parameters: FunctionParameterListSyntax,
    forceQualifiedNames: Bool
) -> MockFunctionNames {
    let base = baseName.safeLowerCamelIdentifier
    let stem: String
    if forceQualifiedNames {
        let suffix = parameters.map { parameter -> String in
            let label = parameter.firstName.text == "_"
                ? "Unlabeled"
                : parameter.firstName.text.identifierStem
            return label + parameter.type.trimmedDescription.identifierStem
        }.joined()
        stem = base + (suffix.isEmpty ? "NoArguments" : suffix)
    } else {
        stem = base
    }

    return MockFunctionNames(
        stem: stem,
        callStructName: "\(stem.capitalizedFirst)Call",
        callsProperty: "\(stem)Calls",
        returnProperty: "\(stem)ReturnValue",
        resultProperty: "\(stem)Result",
        thrownErrorProperty: "\(stem)ThrownError",
        handlerProperty: "\(stem)Handler"
    )
}

private func effectInvocationPrefix(isAsync: Bool, isThrowing: Bool) -> String {
    var tokens: [String] = []
    if isThrowing { tokens.append("try") }
    if isAsync { tokens.append("await") }
    return tokens.isEmpty ? "" : tokens.joined(separator: " ") + " "
}

private func hasAnyModifier(_ modifiers: DeclModifierListSyntax, named names: Set<String>) -> Bool {
    modifiers.contains { modifier in
        names.contains(modifier.name.text)
    }
}

private func unsupportedMemberName(_ decl: DeclSyntax) -> String {
    if let associatedType = decl.as(AssociatedTypeDeclSyntax.self) {
        return associatedType.name.text
    }
    if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
        return subscriptDecl.subscriptKeyword.text
    }
    return decl.trimmedDescription
}

private extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }

    var identifierStem: String {
        let words = splitIntoIdentifierWords()
        guard !words.isEmpty else { return "Value" }
        return words.map(\.capitalizedFirst).joined()
    }

    var safeLowerCamelIdentifier: String {
        let stem = identifierStem
        guard let first = stem.first else { return "value" }
        return String(first).lowercased() + stem.dropFirst()
    }

    private func splitIntoIdentifierWords() -> [String] {
        var words: [String] = []
        var current = ""
        for scalar in unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words
    }
}
