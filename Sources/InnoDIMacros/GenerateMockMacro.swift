//
//  GenerateMockMacro.swift
//  InnoDIMacros
//
//  RFC 0001 (`@GenerateMock`) experimental implementation.
//
//  Stage 1 (skeleton) shipped attribute validation and a tracking note.
//  Stage 2 walks a protocol's member block and emits a
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
            context.emit(
                SimpleDiagnostic.generateMockRequiresProtocol(),
                at: Syntax(node)
            )
            return []
        }

        let mockTypeName = "\(protocolDecl.name.text)Mock"
        let isMainActor = findStandardMainActorAttribute(
            in: protocolDecl.attributes
        ) != nil
        let isSendable = inheritsSendable(protocolDecl)
        let usesConcurrentStorage = isSendable && !isMainActor
        var bodyLines: [String] = []
        var unsupportedMembers: [String] = []
        var missingStubExpressions: [String] = []
        var recordedCallCountExpressions: [String] = []
        var usesNotStubbedError = false
        if let isolation = unsupportedMockIsolation(in: protocolDecl.attributes) {
            unsupportedMembers.append(isolation)
        }
        unsupportedMembers.append(
            contentsOf: unsupportedMockInheritance(in: protocolDecl)
        )
        if protocolDecl.memberBlock.members.isEmpty {
            // Empty protocol — emit the skeleton note so consumers can still
            // confirm the macro plugin sees the attribute.
            context.emit(
                SimpleDiagnostic.generateMockExperimentalSkeleton(
                    protocolName: protocolDecl.name.text
                ),
                at: Syntax(node)
            )
        }

        let functionNames = plannedFunctionNames(in: protocolDecl)
        var functionIndex = 0

        for member in protocolDecl.memberBlock.members {
            if let function = member.decl.as(FunctionDeclSyntax.self) {
                let names = functionNames[functionIndex]
                functionIndex += 1
                if let rendered = renderFunctionMock(
                    function: function,
                    names: names,
                    concurrent: usesConcurrentStorage
                ) {
                    bodyLines.append(rendered.snippet)
                    usesNotStubbedError = usesNotStubbedError || rendered.usesNotStubbedError
                    if let expression = rendered.missingStubExpression {
                        missingStubExpressions.append(expression)
                    }
                    recordedCallCountExpressions.append(
                        rendered.recordedCallCountExpression
                    )
                } else {
                    unsupportedMembers.append(function.name.text)
                }
            } else if let variable = member.decl.as(VariableDeclSyntax.self) {
                if let snippet = renderVariableMock(
                    variable: variable,
                    concurrent: usesConcurrentStorage
                ) {
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

        let declaredPropertyNames = Set(
            protocolDecl.memberBlock.members
                .compactMap { $0.decl.as(VariableDeclSyntax.self) }
                .flatMap { variable in
                    variable.bindings.compactMap {
                        $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                    }
                }
        )
        if !recordedCallCountExpressions.isEmpty,
           declaredPropertyNames.contains("recordedCallCounts") {
            unsupportedMembers.append("recordedCallCounts generated-helper collision")
        }
        if !missingStubExpressions.isEmpty,
           declaredPropertyNames.contains("missingStubSelectors") {
            unsupportedMembers.append("missingStubSelectors generated-helper collision")
        }

        if !unsupportedMembers.isEmpty {
            context.emit(
                SimpleDiagnostic.generateMockUnsupportedMember(
                    memberNames: unsupportedMembers
                ),
                at: Syntax(node)
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
        if !missingStubExpressions.isEmpty {
            let expressions = missingStubExpressions.joined(separator: ",\n            ")
            bodyLines.append(
                """
                    var missingStubSelectors: [String] {
                        [
                            \(expressions)
                        ].compactMap { $0 }
                    }
                """
            )
        }
        if !recordedCallCountExpressions.isEmpty {
            let expressions = recordedCallCountExpressions.joined(
                separator: ",\n            "
            )
            bodyLines.append(
                """
                    var recordedCallCounts: [String: Int] {
                        [
                            \(expressions)
                        ]
                    }
                """
            )
        }

        let bodyJoined = bodyLines.joined(separator: "\n\n")
        let renderedBody: String
        if bodyJoined.isEmpty {
            renderedBody = "    // RFC 0001: no supported members yet — replace with the protocol's full member set."
        } else {
            renderedBody = bodyJoined
        }

        let accessPrefix = mockTypeAccessPrefix(for: protocolDecl)
        let isolationPrefix = isMainActor ? "@MainActor\n" : ""
        let mockDecl: DeclSyntax = """
        /// Auto-generated mock for `\(raw: protocolDecl.name.text)` (RFC 0001 stage 2).
        \(raw: isolationPrefix)\(raw: accessPrefix)final class \(raw: mockTypeName): \(raw: protocolDecl.name.text) {
            init() {}

        \(raw: renderedBody)
        }
        """
        return [mockDecl]
    }
}

private func unsupportedMockInheritance(
    in protocolDecl: ProtocolDeclSyntax
) -> [String] {
    guard let inheritanceClause = protocolDecl.inheritanceClause else {
        return []
    }
    return inheritanceClause.inheritedTypes.compactMap { inherited in
        guard !["AnyObject", "Sendable"].contains(
            inheritedTypeBaseName(inherited.type)
        ) else {
            return nil
        }
        return "\(inherited.type.trimmedDescription) inheritance"
    }
}

private func inheritsSendable(_ protocolDecl: ProtocolDeclSyntax) -> Bool {
    protocolDecl.inheritanceClause?.inheritedTypes.contains {
        inheritedTypeBaseName($0.type) == "Sendable"
    } == true
}

func unsupportedMockIsolation(
    in attributes: AttributeListSyntax?
) -> String? {
    if let actorName = detectConflictingGlobalActor(in: attributes) {
        return "@\(actorName) isolation"
    }
    return nil
}

private func mockTypeAccessPrefix(for protocolDecl: ProtocolDeclSyntax) -> String {
    // A peer of a private/fileprivate protocol cannot legally expose a wider
    // conformance. Keep all other generated mocks internal so this
    // experimental macro does not expand a public package API implicitly.
    for modifier in protocolDecl.modifiers {
        switch modifier.name.text {
        case "private", "fileprivate":
            return "\(modifier.name.text) "
        default:
            continue
        }
    }
    return ""
}

private func inheritedTypeBaseName(_ type: TypeSyntax) -> String? {
    let trimmed = type.trimmed
    if let attributed = trimmed.as(AttributedTypeSyntax.self) {
        return inheritedTypeBaseName(attributed.baseType)
    }
    if let identifier = trimmed.as(IdentifierTypeSyntax.self) {
        return identifier.name.text
    }
    if let member = trimmed.as(MemberTypeSyntax.self) {
        return member.name.text
    }
    return trimmed.trimmedDescription.split(separator: ".").last.map(String.init)
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
