//
//  GenerateMockMacro.swift
//  InnoDIMacros
//
//  RFC 0001 (`@GenerateMock`) experimental implementation.
//
//  Stage 1 (skeleton) shipped attribute validation and a tracking note.
//  Stage 2 (this file) walks a protocol's member block and emits a
//  call-recording mock peer for the simplest method shape: synchronous,
//  non-throwing functions plus settable `var` requirements. async,
//  throws, mutating, and associated-type cases continue to receive a
//  scoped diagnostic until the corresponding stage in RFC 0001 lands.
//

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

        for member in protocolDecl.memberBlock.members {
            if let function = member.decl.as(FunctionDeclSyntax.self) {
                if let snippet = renderFunctionMock(function: function) {
                    bodyLines.append(snippet)
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
                unsupportedMembers.append(member.decl.trimmedDescription)
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

private func renderFunctionMock(function: FunctionDeclSyntax) -> String? {
    let signature = function.signature
    let isAsync = signature.effectSpecifiers?.asyncSpecifier != nil
    let isThrowing = signature.effectSpecifiers?.throwsClause != nil
    if isAsync || isThrowing {
        return nil
    }

    let baseName = function.name.text
    let parameters = signature.parameterClause.parameters
    let callParameters = parameters.map { parameter -> (label: String, name: String, type: String) in
        let label = parameter.firstName.text
        let internalName = (parameter.secondName?.text ?? parameter.firstName.text)
        let typeText = parameter.type.trimmedDescription
        return (label, internalName, typeText)
    }

    let returnsVoid: Bool
    if let returnClause = signature.returnClause {
        returnsVoid = returnClause.type.trimmedDescription == "Void"
    } else {
        returnsVoid = true
    }

    let returnTypeRendered = signature.returnClause?.type.trimmedDescription ?? "Void"
    let parametersRendered = parameters.map { $0.trimmedDescription }.joined(separator: ", ")

    let callStructName = "\(baseName.capitalizedFirst)Call"
    let callsProperty = "\(baseName)Calls"
    let returnProperty = "\(baseName)ReturnValue"

    var snippetLines: [String] = []

    let callFields = callParameters
        .map { "        let \($0.name): \($0.type)" }
        .joined(separator: "\n")
    snippetLines.append("    struct \(callStructName) {")
    if !callFields.isEmpty {
        snippetLines.append(callFields)
    }
    snippetLines.append("    }")
    snippetLines.append("    private(set) var \(callsProperty): [\(callStructName)] = []")

    if !returnsVoid {
        snippetLines.append("    var \(returnProperty): \(returnTypeRendered)?")
    }

    let recordArgs = callParameters
        .map { "\($0.name): \($0.name)" }
        .joined(separator: ", ")
    snippetLines.append("    func \(baseName)(\(parametersRendered)) -> \(returnTypeRendered) {")
    snippetLines.append("        \(callsProperty).append(.init(\(recordArgs)))")
    if !returnsVoid {
        snippetLines.append("        guard let value = \(returnProperty) else {")
        snippetLines.append("            preconditionFailure(\"\(returnProperty) was not set on \\(type(of: self)) before \(baseName) was invoked\")")
        snippetLines.append("        }")
        snippetLines.append("        return value")
    }
    snippetLines.append("    }")

    return snippetLines.joined(separator: "\n")
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

private extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
