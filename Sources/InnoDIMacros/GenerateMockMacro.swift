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
import SwiftSyntaxBuilder
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
        var sections: [MockMembers] = []
        var unsupportedMembers: [String] = []
        var missingStubExpressions: [ExprSyntax] = []
        var recordedCallCounts: [DictionaryElementSyntax] = []
        var resetCallStatements: [CodeBlockItemSyntax] = []
        var resetStubStatements: [CodeBlockItemSyntax] = []
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

        let declaredMemberNames = Set(protocolDecl.memberBlock.members.flatMap { member -> [String] in
            if let function = member.decl.as(FunctionDeclSyntax.self) {
                return [function.name.text.unescapedIdentifier]
            }
            return member.decl.as(VariableDeclSyntax.self)?.bindings.compactMap {
                $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text.unescapedIdentifier
            } ?? []
        })
        let stateNames = MockStateNames(reserving: declaredMemberNames)
        let genericTypeNames = Set(protocolDecl.memberBlock.members.flatMap { member in
            member.decl.as(FunctionDeclSyntax.self)?.genericParameterClause?
                .parameters.map { $0.name.text.unescapedIdentifier } ?? []
        })
        let concreteSelfType: String
        if genericTypeNames.contains(mockTypeName),
           protocolDecl.memberBlock.tokens(viewMode: .sourceAccurate).contains(where: { $0.text == "Self" }) {
            // Bind outside every generic method before rewriting Self. A
            // generic parameter may legally have the generated class's name.
            concreteSelfType = freshMockIdentifier(
                "_InnoDIMockSelf",
                reserving: declaredMemberNames.union(genericTypeNames)
            )
            sections.append(MockMembers("typealias \(raw: concreteSelfType) = \(raw: mockTypeName)"))
        } else {
            concreteSelfType = mockTypeName
        }
        let typeRewriter = MockSelfTypeRewriter(mockTypeName: concreteSelfType)
        let functionNames = plannedFunctionNames(
            in: protocolDecl,
            concurrent: usesConcurrentStorage
        )
        var functionIndex = 0

        for member in protocolDecl.memberBlock.members {
            if let function = member.decl.as(FunctionDeclSyntax.self) {
                let names = functionNames[functionIndex]
                functionIndex += 1
                if let reason = unsupportedMockFunctionShape(function) {
                    unsupportedMembers.append("\(function.name.text) (\(reason))")
                    continue
                }
                if let rendered = renderFunctionMock(
                    function: typeRewriter.rewrite(function).cast(FunctionDeclSyntax.self),
                    names: names,
                    concurrent: usesConcurrentStorage,
                    stateNames: stateNames
                ) {
                    sections.append(rendered.members)
                    usesNotStubbedError = usesNotStubbedError || rendered.usesNotStubbedError
                    if let expression = rendered.missingStubExpression {
                        missingStubExpressions.append(expression)
                    }
                    recordedCallCounts.append(rendered.recordedCallCount)
                    resetCallStatements.append(rendered.resetCallStatement)
                    resetStubStatements.append(
                        contentsOf: rendered.resetStubStatements
                    )
                } else {
                    unsupportedMembers.append(function.name.text)
                }
            } else if let variable = member.decl.as(VariableDeclSyntax.self) {
                if let rendered = renderVariableMock(
                    variable: typeRewriter.rewrite(variable).cast(VariableDeclSyntax.self),
                    concurrent: usesConcurrentStorage,
                    stateNames: stateNames,
                    reserving: declaredMemberNames
                ) {
                    sections.append(rendered.members)
                    missingStubExpressions.append(
                        rendered.missingStubExpression
                    )
                    resetStubStatements.append(
                        contentsOf: rendered.resetStubStatements
                    )
                } else {
                    unsupportedMembers.append(
                        variable.bindings.first?.pattern.trimmedDescription ?? "<unknown>"
                    )
                }
            } else {
                unsupportedMembers.append(unsupportedMemberName(member.decl))
            }
        }

        if !recordedCallCounts.isEmpty,
           declaredMemberNames.contains("recordedCallCounts") {
            unsupportedMembers.append("recordedCallCounts generated-helper collision")
        }
        if !missingStubExpressions.isEmpty,
           declaredMemberNames.contains("missingStubSelectors") {
            unsupportedMembers.append("missingStubSelectors generated-helper collision")
        }
        let hasResetSurface = !resetCallStatements.isEmpty
            || !resetStubStatements.isEmpty
        if hasResetSurface {
            for helperName in [
                "innoDIReset",
                "innoDICallHistoryGeneration",
                "innoDICallHistorySnapshot"
            ] where declaredMemberNames.contains(helperName) {
                unsupportedMembers.append("\(helperName) generated-helper collision")
            }
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
            sections.insert(
                MockMembers("""
                    struct \(raw: stateNames.notStubbedError): Error, CustomStringConvertible {
                        let selector: String
                        var description: String { "InnoDI mock selector '\\(selector)' was not stubbed before invocation." }
                    }
                """),
                at: 0
            )
        }
        if hasResetSurface {
            sections.insert(
                usesConcurrentStorage
                    ? MockMembers("""
                        private let \(raw: stateNames.concurrentState) = InnoDITesting.DIConcurrentMockState()
                    """)
                    : MockMembers("""
                        private var \(raw: stateNames.generation): UInt64 = 0
                    """),
                at: 0
            )
        }
        if !missingStubExpressions.isEmpty {
            if usesConcurrentStorage {
                let expressions = lineSeparatedElements(missingStubExpressions, indentation: 16)
                sections.append(MockMembers("""
                    var missingStubSelectors: [String] {
                        \(raw: stateNames.concurrentState).withCriticalRegion { _ in
                            [\(expressions)
                            ].compactMap { $0 }
                        }
                    }
                """))
            } else {
                let expressions = lineSeparatedElements(missingStubExpressions, indentation: 12)
                sections.append(MockMembers("""
                    var missingStubSelectors: [String] {
                        [\(expressions)
                        ].compactMap { $0 }
                    }
                """))
            }
        }
        if !recordedCallCounts.isEmpty {
            if usesConcurrentStorage {
                let entries = lineSeparatedElements(recordedCallCounts, indentation: 16)
                sections.append(MockMembers("""
                    var recordedCallCounts: [String: Int] {
                        \(raw: stateNames.concurrentState).withCriticalRegion { _ in
                            [\(entries)
                            ]
                        }
                    }
                """))
            } else {
                let entries = lineSeparatedElements(recordedCallCounts, indentation: 12)
                sections.append(MockMembers("""
                    var recordedCallCounts: [String: Int] {
                        [\(entries)
                        ]
                    }
                """))
            }
        }
        if hasResetSurface {
            sections.append(
                MockMembers(
                    renderMockResetSurface(
                        concurrent: usesConcurrentStorage,
                        stateNames: stateNames,
                        recordedCallCounts: recordedCallCounts,
                        resetCallStatements: resetCallStatements,
                        resetStubStatements: resetStubStatements
                    )
                )
            )
        }

        let accessPrefix = mockTypeAccessPrefix(for: protocolDecl)
        let isNonisolated = protocolDecl.modifiers.contains { $0.name.text == "nonisolated" }
        let isolationPrefix = isMainActor ? "@MainActor\n" : (isNonisolated ? "nonisolated " : "")
        let body = mockBodyMembers(sections)
        let mockDecl: DeclSyntax
        if body.isEmpty {
            mockDecl = """
            /// Auto-generated mock for `\(raw: protocolDecl.name.text)` (RFC 0001 stage 2).
            \(raw: isolationPrefix)\(raw: accessPrefix)final class \(raw: mockTypeName): \(raw: protocolDecl.name.text) {
                init() {}

                // RFC 0001: no supported members yet — replace with the protocol's full member set.
            }
            """
        } else {
            mockDecl = """
            /// Auto-generated mock for `\(raw: protocolDecl.name.text)` (RFC 0001 stage 2).
            \(raw: isolationPrefix)\(raw: accessPrefix)final class \(raw: mockTypeName): \(raw: protocolDecl.name.text) {
                init() {}\(body)
            }
            """
        }
        return [mockDecl]
    }
}

/// The class members after `init() {}`, with a blank line before each
/// section.
private func mockBodyMembers(_ sections: [MockMembers]) -> MemberBlockItemListSyntax {
    MemberBlockItemListSyntax(
        sections.flatMap { section in
            section.items.enumerated().map { index, member in
                index == 0
                    ? member.with(\.leadingTrivia, .newlines(2) + member.leadingTrivia)
                    : member
            }
        }
    )
}

/// Array elements, one per line at `indentation`. The literal interpolates
/// them right after `[` so the builder does not re-indent them.
private func lineSeparatedElements(
    _ expressions: [ExprSyntax],
    indentation: Int
) -> ArrayElementListSyntax {
    ArrayElementListSyntax(
        expressions.enumerated().map { index, expression in
            ArrayElementSyntax(
                leadingTrivia: .newline + .spaces(indentation),
                expression: expression,
                trailingComma: index == expressions.count - 1 ? nil : .commaToken()
            )
        }
    )
}

/// Dictionary entries, spaced like ``lineSeparatedElements(_:indentation:)``.
private func lineSeparatedElements(
    _ entries: [DictionaryElementSyntax],
    indentation: Int
) -> DictionaryElementListSyntax {
    DictionaryElementListSyntax(
        entries.enumerated().map { index, entry in
            entry
                .with(\.leadingTrivia, .newline + .spaces(indentation))
                .with(\.trailingComma, index == entries.count - 1 ? nil : .commaToken())
        }
    )
}

/// The snapshot's call counts, one per line at 16 spaces, or the `:` of an
/// empty dictionary literal when no requirement records calls.
private func resetSnapshotCounts(_ entries: [DictionaryElementSyntax]) -> Syntax {
    guard !entries.isEmpty else {
        return Syntax(TokenSyntax.colonToken(leadingTrivia: .spaces(16)))
    }
    return Syntax(
        DictionaryElementListSyntax(
            entries.enumerated().map { index, entry in
                entry
                    .with(\.leadingTrivia, index == 0 ? .spaces(16) : .newline + .spaces(16))
                    .with(\.trailingComma, index == entries.count - 1 ? nil : .commaToken())
            }
        )
    )
}

/// `statements`, one per line at `spaces`.
private func lineIndentedStatements(
    _ statements: [CodeBlockItemSyntax],
    spaces: Int
) -> CodeBlockItemListSyntax {
    CodeBlockItemListSyntax(
        statements.enumerated().map { index, statement in
            statement.with(
                \.leadingTrivia,
                index == 0 ? .spaces(spaces) : .newline + .spaces(spaces)
            )
        }
    )
}

private func renderMockResetSurface(
    concurrent: Bool,
    stateNames: MockStateNames,
    recordedCallCounts: [DictionaryElementSyntax],
    resetCallStatements: [CodeBlockItemSyntax],
    resetStubStatements: [CodeBlockItemSyntax]
) -> MemberBlockItemListSyntax {
    let counts = resetSnapshotCounts(recordedCallCounts)

    if concurrent {
        let callReset = lineIndentedStatements(resetCallStatements, spaces: 12)
        let stubReset = lineIndentedStatements(resetStubStatements, spaces: 16)
        return """
            enum InnoDIResetScope: Sendable {
                case calls
                case all
            }

            struct InnoDICallHistorySnapshot: Equatable, Sendable {
                let generation: UInt64
                let recordedCallCounts: [String: Int]
            }

            var innoDICallHistoryGeneration: UInt64 {
                \(raw: stateNames.concurrentState).withCriticalRegion { $0 }
            }

            var innoDICallHistorySnapshot: InnoDICallHistorySnapshot {
                \(raw: stateNames.concurrentState).withCriticalRegion { generation in
                    .init(
                        generation: generation,
                        recordedCallCounts: [
        \(counts)
                        ]
                    )
                }
            }

            @discardableResult
            func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
                \(raw: stateNames.concurrentState).reset { generation in
                    let snapshot: InnoDICallHistorySnapshot = .init(
                        generation: generation,
                        recordedCallCounts: [
        \(counts)
                        ]
                    )
        \(callReset)
                    if scope == .all {
        \(stubReset)
                    }
                    return snapshot
                }
            }
        """
    }

    let callReset = lineIndentedStatements(resetCallStatements, spaces: 8)
    let stubReset = lineIndentedStatements(resetStubStatements, spaces: 12)
    return """
        enum InnoDIResetScope: Sendable {
            case calls
            case all
        }

        struct InnoDICallHistorySnapshot: Equatable, Sendable {
            let generation: UInt64
            let recordedCallCounts: [String: Int]
        }

        var innoDICallHistoryGeneration: UInt64 {
            \(raw: stateNames.generation)
        }

        var innoDICallHistorySnapshot: InnoDICallHistorySnapshot {
            .init(
                generation: \(raw: stateNames.generation),
                recordedCallCounts: [
    \(counts)
                ]
            )
        }

        @discardableResult
        func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
            let snapshot = innoDICallHistorySnapshot
    \(callReset)
            if scope == .all {
    \(stubReset)
            }
            \(raw: stateNames.generation) &+= 1
            return snapshot
        }
    """
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
