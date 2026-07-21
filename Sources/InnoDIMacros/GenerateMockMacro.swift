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
            context.emit(
                SimpleDiagnostic.generateMockRequiresProtocol(),
                at: Syntax(node)
            )
            return []
        }

        let mockTypeName = "\(protocolDecl.name.text)Mock"
        var bodyLines: [String] = []
        var unsupportedMembers: [String] = []
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
                    names: names
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

        let bodyJoined = bodyLines.joined(separator: "\n\n")
        let renderedBody: String
        if bodyJoined.isEmpty {
            renderedBody = "    // RFC 0001: no supported members yet — replace with the protocol's full member set."
        } else {
            renderedBody = bodyJoined
        }

        let accessPrefix = mockTypeAccessPrefix(for: protocolDecl)
        let mockDecl: DeclSyntax = """
        /// Auto-generated mock for `\(raw: protocolDecl.name.text)` (RFC 0001 stage 2).
        \(raw: accessPrefix)final class \(raw: mockTypeName): \(raw: protocolDecl.name.text) {
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

private func unsupportedMockInheritance(
    in protocolDecl: ProtocolDeclSyntax
) -> [String] {
    guard let inheritanceClause = protocolDecl.inheritanceClause else {
        return []
    }
    return inheritanceClause.inheritedTypes.compactMap { inherited in
        guard inheritedTypeBaseName(inherited.type) != "AnyObject" else {
            return nil
        }
        return "\(inherited.type.trimmedDescription) inheritance"
    }
}

private func unsupportedMockIsolation(
    in attributes: AttributeListSyntax?
) -> String? {
    if findStandardMainActorAttribute(in: attributes) != nil {
        return "@MainActor isolation"
    }
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

private struct MockFunctionNames {
    let stem: String
    let callStructName: String
    let callsProperty: String
    let returnProperty: String
    let resultProperty: String
    let thrownErrorProperty: String
    let handlerProperty: String

    func generatedValueNames(for function: FunctionDeclSyntax) -> Set<String> {
        let isGeneric = function.genericParameterClause != nil
        let isThrowing = function.signature.effectSpecifiers?.throwsClause != nil
        let returnsVoid = isVoidReturnType(
            function.signature.returnClause?.type.trimmedDescription
        )

        var names: Set<String> = [callsProperty]
        if isGeneric {
            names.insert(handlerProperty)
        } else if !returnsVoid {
            names.insert(isThrowing ? resultProperty : returnProperty)
        } else if isThrowing {
            names.insert(thrownErrorProperty)
        }
        return names
    }
}

private func renderFunctionMock(
    function: FunctionDeclSyntax,
    names: MockFunctionNames
) -> RenderedFunctionMock? {
    if unsupportedMockIsolation(in: function.attributes) != nil {
        return nil
    }
    if function.modifiers.contains(where: { $0.name.text != "mutating" }) {
        return nil
    }
    if hasUnsupportedThrowsClause(function.signature) {
        return nil
    }
    let isGeneric = function.genericParameterClause != nil
    if isGeneric {
        return renderGenericFunctionMock(function: function, names: names)
    }
    return renderTypedFunctionMock(function: function, names: names)
}

private func renderTypedFunctionMock(
    function: FunctionDeclSyntax,
    names: MockFunctionNames
) -> RenderedFunctionMock? {
    let signature = function.signature
    let isAsync = signature.effectSpecifiers?.asyncSpecifier != nil
    let isThrowing = signature.effectSpecifiers?.throwsClause != nil

    let baseName = function.name.text
    let parameters = signature.parameterClause.parameters
    guard let callParameters = renderableCallParameters(parameters) else {
        return nil
    }

    let returnsVoid = isVoidReturnType(signature.returnClause?.type.trimmedDescription)

    let returnTypeRendered = signature.returnClause?.type.trimmedDescription ?? "Void"
    if !returnsVoid && isOpaqueType(returnTypeRendered) {
        return nil
    }
    let parametersRendered = parameters.map { $0.trimmedDescription }.joined(separator: ", ")
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
                "    var \(names.resultProperty): Result<\(returnTypeRendered), Error> = .failure(_InnoDIMockNotStubbed(selector: \"\(names.resultProperty)\"))"
            )
        } else {
            snippetLines.append("    var \(names.returnProperty): \(optionalStorageType(returnTypeRendered))")
        }
    } else if isThrowing {
        // Even a Void-returning throwing function needs an opt-in error
        // hook so tests can simulate the failure path.
        snippetLines.append("    var \(names.thrownErrorProperty): Error?")
    }

    let recordArgs = callParameters
        .map { "\($0.label): \($0.name)" }
        .joined(separator: ", ")
    let returnFragment = returnsVoid ? "" : " -> \(returnTypeRendered)"
    snippetLines.append("    func \(baseName)(\(parametersRendered))\(effectSpecifiersJoined)\(returnFragment) {")
    snippetLines.append("        \(names.callsProperty).append(.init(\(recordArgs)))")
    if !returnsVoid {
        if isThrowing {
            snippetLines.append("        return try \(names.resultProperty).get()")
        } else {
            snippetLines.append("        guard let value = \(names.returnProperty) else {")
            snippetLines.append("            preconditionFailure(\"\(names.returnProperty) was not set on \\(Self.self) before \(baseName) was invoked\")")
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
    names: MockFunctionNames
) -> RenderedFunctionMock? {
    let signature = function.signature
    let isAsync = signature.effectSpecifiers?.asyncSpecifier != nil
    let isThrowing = signature.effectSpecifiers?.throwsClause != nil

    let baseName = function.name.text
    let parameters = signature.parameterClause.parameters
    guard let callParameters = renderableCallParameters(parameters, eraseTypes: true) else {
        return nil
    }
    let parametersRendered = parameters.map { $0.trimmedDescription }.joined(separator: ", ")
    let returnTypeRendered = signature.returnClause?.type.trimmedDescription ?? "Void"
    let returnsVoid = isVoidReturnType(signature.returnClause?.type.trimmedDescription)
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
    let recordArgs = callParameters.map { "\($0.label): \($0.name)" }.joined(separator: ", ")
    snippetLines.append("        \(names.callsProperty).append(.init(\(recordArgs)))")
    if returnsVoid {
        snippetLines.append("        if let handler = \(names.handlerProperty) {")
        snippetLines.append("            \(invocationPrefix)handler(\(handlerArgumentArray))")
        snippetLines.append("        }")
    } else {
        snippetLines.append("        guard let handler = \(names.handlerProperty) else {")
        snippetLines.append("            preconditionFailure(\"\(names.handlerProperty) was not set on \\(Self.self) before \(baseName) was invoked\")")
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
    if unsupportedMockIsolation(in: variable.attributes) != nil {
        return nil
    }
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
    let escapedName = name.escapedSwiftIdentifier
    let storageName = "__innodi_\(name.safeLowerCamelIdentifier)_\(name.stableIdentifierSuffix)StubValue"
    let storageType = optionalStorageType(type)
    return """
        private var \(storageName): \(storageType)
        var \(escapedName): \(type) {
            get {
                guard let value = \(storageName) else {
                    preconditionFailure("\(name) was not set on \\(Self.self) before it was read")
                }
                return value
            }
            set {
                \(storageName) = newValue
            }
        }
    """
}

private func renderableCallParameters(
    _ parameters: FunctionParameterListSyntax,
    eraseTypes: Bool = false
) -> [(label: String, name: String, type: String)]? {
    var usedNames: [String: Int] = [:]
    var rendered: [(label: String, name: String, type: String)] = []
    for (index, parameter) in parameters.enumerated() {
        let internalName = (parameter.secondName?.text ?? parameter.firstName.text)
        let baseFieldName = internalName == "_"
            ? "value\(index + 1)"
            : internalName.unescapedIdentifier.safeLowerCamelIdentifier
        let count = usedNames[baseFieldName, default: 0]
        usedNames[baseFieldName] = count + 1
        let unescapedFieldName = count == 0 ? baseFieldName : "\(baseFieldName)\(count + 1)"
        guard let typeText = renderableCallRecordType(parameter.type.trimmedDescription, eraseTypes: eraseTypes) else {
            return nil
        }
        rendered.append((unescapedFieldName, unescapedFieldName.escapedSwiftIdentifier, typeText))
    }
    return rendered
}

private func renderableCallRecordType(_ typeText: String, eraseTypes: Bool) -> String? {
    if typeText.hasPrefix("inout ") {
        return nil
    }
    if eraseTypes {
        return "Any"
    }
    if isOpaqueType(typeText) {
        return nil
    }

    return typeText
        .replacingOccurrences(of: "@escaping ", with: "")
        .replacingOccurrences(of: "@autoclosure ", with: "")
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

    return makeFunctionNames(stem: stem)
}

private func makeFunctionNames(stem: String) -> MockFunctionNames {
    MockFunctionNames(
        stem: stem,
        callStructName: "\(stem.capitalizedFirst)Call",
        callsProperty: "\(stem)Calls",
        returnProperty: "\(stem)ReturnValue",
        resultProperty: "\(stem)Result",
        thrownErrorProperty: "\(stem)ThrownError",
        handlerProperty: "\(stem)Handler"
    )
}

private func plannedFunctionNames(
    in protocolDecl: ProtocolDeclSyntax
) -> [MockFunctionNames] {
    let functions = protocolDecl.memberBlock.members.compactMap {
        $0.decl.as(FunctionDeclSyntax.self)
    }
    let overloadCounts = Dictionary(
        grouping: functions.map { $0.name.text },
        by: { $0 }
    ).mapValues(\.count)
    let declaredValueNames = Set(
        protocolDecl.memberBlock.members.flatMap { member -> [String] in
            guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                return []
            }
            return variable.bindings.compactMap {
                $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            }
        }
    )
    let candidates = functions.map { function in
        makeFunctionNames(
            baseName: function.name.text,
            parameters: function.signature.parameterClause.parameters,
            forceQualifiedNames: function.genericParameterClause != nil
                || (overloadCounts[function.name.text] ?? 0) > 1
        )
    }
    let stemCounts = Dictionary(
        grouping: candidates.map(\.stem),
        by: { $0 }
    ).mapValues(\.count)

    return zip(functions, candidates).map { function, candidate in
        let collidesWithFunction = (stemCounts[candidate.stem] ?? 0) > 1
        let collidesWithProperty = !candidate
            .generatedValueNames(for: function)
            .isDisjoint(with: declaredValueNames)
        guard collidesWithFunction || collidesWithProperty else {
            return candidate
        }

        let signatureIdentity = [
            function.name.text,
            function.genericParameterClause?.trimmedDescription ?? "",
            function.signature.trimmedDescription,
            function.genericWhereClause?.trimmedDescription ?? "",
        ].joined(separator: "|")
        return makeFunctionNames(
            stem: candidate.stem
                + signatureIdentity.stableIdentifierSuffix.capitalizedFirst
        )
    }
}

private func effectInvocationPrefix(isAsync: Bool, isThrowing: Bool) -> String {
    var tokens: [String] = []
    if isThrowing { tokens.append("try") }
    if isAsync { tokens.append("await") }
    return tokens.isEmpty ? "" : tokens.joined(separator: " ") + " "
}

private func hasUnsupportedThrowsClause(_ signature: FunctionSignatureSyntax) -> Bool {
    guard let throwsClause = signature.effectSpecifiers?.throwsClause else {
        return false
    }
    return throwsClause.trimmedDescription != "throws"
}

private func isOpaqueType(_ typeText: String) -> Bool {
    typeText == "some" || typeText.hasPrefix("some ") || typeText.contains(" some ")
}

private func isVoidReturnType(_ typeText: String?) -> Bool {
    guard let typeText else {
        return true
    }
    return typeText == "Void" || typeText == "()" || typeText == "(Void)"
}

private func optionalStorageType(_ typeText: String) -> String {
    if typeText.hasPrefix("any ")
        || typeText.hasSuffix("?")
        || typeText.contains("->")
        || typeText.contains("&") {
        return "(\(typeText))?"
    }
    return "\(typeText)?"
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
    var unescapedIdentifier: String {
        var value = self
        if value.first == "`" {
            value.removeFirst()
        }
        if value.last == "`" {
            value.removeLast()
        }
        return value
    }

    var escapedSwiftIdentifier: String {
        if swiftKeywords.contains(self) {
            return "`\(self)`"
        }
        return self
    }

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

    var stableIdentifierSuffix: String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "h%016llx", hash)
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

private let swiftKeywords: Set<String> = [
    "associatedtype",
    "class",
    "deinit",
    "enum",
    "extension",
    "fileprivate",
    "func",
    "import",
    "init",
    "inout",
    "internal",
    "let",
    "open",
    "operator",
    "private",
    "precedencegroup",
    "protocol",
    "public",
    "rethrows",
    "static",
    "struct",
    "subscript",
    "typealias",
    "var",
    "break",
    "case",
    "catch",
    "continue",
    "default",
    "defer",
    "do",
    "else",
    "fallthrough",
    "for",
    "guard",
    "if",
    "in",
    "repeat",
    "return",
    "throw",
    "switch",
    "where",
    "while",
    "as",
    "Any",
    "false",
    "is",
    "nil",
    "self",
    "Self",
    "super",
    "throws",
    "true",
    "try",
]
