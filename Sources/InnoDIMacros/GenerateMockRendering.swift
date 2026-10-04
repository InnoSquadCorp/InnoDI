import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

// Protocol requirement lowering and generated mock source rendering.
//
// Each renderer builds a requirement's mock members as syntax, one member per
// line in source order. The member text matches the earlier line-based
// renderer, so expansions and snapshots are unchanged.

/// Generated mock members in source order, one per line.
struct MockMembers {
    private(set) var items: [MemberBlockItemSyntax] = []

    init(_ members: MemberBlockItemListSyntax = []) {
        append(members)
    }

    var isEmpty: Bool { items.isEmpty }

    /// Appends `members`, starting the first of them on a new line.
    mutating func append(_ members: MemberBlockItemListSyntax) {
        for (index, member) in members.enumerated() {
            if index == 0, !items.isEmpty {
                items.append(member.with(\.leadingTrivia, .newline + member.leadingTrivia))
            } else {
                items.append(member)
            }
        }
    }
}

struct RenderedFunctionMock {
    let members: MockMembers
    let usesNotStubbedError: Bool
    let missingStubExpression: ExprSyntax?
    let recordedCallCount: DictionaryElementSyntax
    let resetCallStatement: CodeBlockItemSyntax
    let resetStubStatements: [CodeBlockItemSyntax]
}
func renderFunctionMock(
    function: FunctionDeclSyntax,
    names: MockFunctionNames,
    concurrent: Bool = false,
    stateNames: MockStateNames = MockStateNames()
) -> RenderedFunctionMock? {
    if findStandardMainActorAttribute(in: function.attributes) != nil {
        return nil
    }
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
    if isGeneric,
       typedThrowsFailureType(
           function.signature.effectSpecifiers?.throwsClause?.trimmedDescription
       ) != nil {
        return nil
    }
    if concurrent {
        guard !isGeneric else { return nil }
        return renderConcurrentTypedFunctionMock(
            function: function,
            names: names,
            stateNames: stateNames
        )
    }
    if isGeneric {
        return renderGenericFunctionMock(function: function, names: names, stateNames: stateNames)
    }
    return renderTypedFunctionMock(function: function, names: names, stateNames: stateNames)
}

private func renderConcurrentTypedFunctionMock(
    function: FunctionDeclSyntax,
    names: MockFunctionNames,
    stateNames: MockStateNames
) -> RenderedFunctionMock? {
    let scope = MockFunctionScope(function)
    let generation = scope.local("generation")
    let result = scope.local("result")
    let error = scope.local("error")
    let state = scope.member(stateNames.concurrentState)
    let signature = function.signature
    let isAsync = signature.effectSpecifiers?.asyncSpecifier != nil
    let throwsSpelling = signature.effectSpecifiers?.throwsClause?.trimmedDescription
    let isThrowing = throwsSpelling != nil
    let typedFailure = typedThrowsFailureType(throwsSpelling)

    let baseName = function.name.text
    let parameters = signature.parameterClause.parameters
    guard var callParameters = renderableCallParameters(parameters) else {
        return nil
    }
    // Ownership parameters are mutable bindings in Swift's capture checking.
    // Copy before entering either @Sendable critical-region closure, then
    // capture the immutable local instead of the borrowed/consuming parameter.
    var capturedNames = Set(callParameters.map(\.argumentIdentifier))
    var captures: [CodeBlockItemSyntax] = []
    for index in callParameters.indices where callParameters[index].requiresCopy {
        let name = freshMockIdentifier(
            "__innodi\(callParameters[index].fieldLabel.capitalizedFirst)Copy",
            reserving: capturedNames
        )
        capturedNames.insert(name)
        captures.append("let \(raw: name) = copy \(raw: callParameters[index].argumentIdentifier)")
        callParameters[index].argumentIdentifier = name
        callParameters[index].requiresCopy = false
    }
    let returnsVoid = isVoidReturnType(
        signature.returnClause?.type.trimmedDescription
    )
    let returnType = signature.returnClause?.type.trimmedDescription ?? "Void"
    if !returnsVoid && isOpaqueType(returnType) { return nil }
    let parameterList = functionParameterList(callParameters)
    var effects: [String] = []
    if isAsync { effects.append("async") }
    if let throwsSpelling { effects.append(throwsSpelling) }
    let effectsRendered = effects.isEmpty ? "" : " " + effects.joined(separator: " ")
    let callBox = "__innodi_\(names.callsProperty)Box"
    let initializedRecordArgs = recordArguments(
        callParameters,
        generation: generation
    )
    let stubbedBox = "__innodi_\(names.stem)StubbedBox"
    var resetStubStatements: [CodeBlockItemSyntax] = []
    var members = MockMembers("""
        struct \(raw: names.callStructName): Sendable {
            let generation: UInt64\(callFieldMembers(callParameters))
        }
        private let \(raw: callBox) = InnoDITesting.DIConcurrentValueBox<[\(raw: names.callStructName)]>([])
        var \(raw: names.callsProperty): [\(raw: names.callStructName)] {
            \(raw: stateNames.concurrentState).withCriticalRegion { _ in \(raw: callBox).snapshot() }
        }
    """)

    if let typedFailure {
        let box = "__innodi_\(names.resultProperty)Box"
        let successType = returnsVoid ? "Void" : returnType
        let resultType = "Result<\(successType), \(typedFailure)>?"
        members.append("""
            private let \(raw: box) = InnoDITesting.DIConcurrentValueBox<\(raw: resultType)>(nil)
            private let \(raw: stubbedBox) = InnoDITesting.DIConcurrentValueBox(false)
            var \(raw: names.resultProperty): \(raw: resultType) {
                get { \(raw: state).withCriticalRegion { _ in \(raw: box).snapshot() } }
                set {
                    \(raw: state).withCriticalRegion { _ in
                        \(raw: box).replace(with: newValue)
                        \(raw: stubbedBox).replace(with: newValue != nil)
                    }
                }
            }
        """)
        resetStubStatements.append("\(raw: box).replace(with: nil)")
        resetStubStatements.append("\(raw: stubbedBox).replace(with: false)")
    } else if !returnsVoid {
        if isThrowing {
            let box = "__innodi_\(names.resultProperty)Box"
            members.append("""
                private let \(raw: box) = InnoDITesting.DIConcurrentValueBox<Result<\(raw: returnType), Error>>(.failure(\(raw: stateNames.notStubbedError)(selector: \(literal: names.resultProperty))))
                private let \(raw: stubbedBox) = InnoDITesting.DIConcurrentValueBox(false)
                var \(raw: names.resultProperty): Result<\(raw: returnType), Error> {
                    get { \(raw: state).withCriticalRegion { _ in \(raw: box).snapshot() } }
                    set {
                        \(raw: state).withCriticalRegion { _ in
                            \(raw: box).replace(with: newValue)
                            \(raw: stubbedBox).replace(with: true)
                        }
                    }
                }
            """)
            resetStubStatements.append("\(raw: box).replace(with: .failure(\(raw: stateNames.notStubbedError)(selector: \(literal: names.resultProperty))))")
            resetStubStatements.append("\(raw: stubbedBox).replace(with: false)")
        } else {
            let box = "__innodi_\(names.returnProperty)Box"
            let storageType = optionalStorageType(returnType)
            members.append("""
                private let \(raw: box) = InnoDITesting.DIConcurrentValueBox<\(raw: storageType)>(nil)
                private let \(raw: stubbedBox) = InnoDITesting.DIConcurrentValueBox(false)
                var \(raw: names.returnProperty): \(raw: storageType) {
                    get { \(raw: state).withCriticalRegion { _ in \(raw: box).snapshot() } }
                    set {
                        \(raw: state).withCriticalRegion { _ in
                            \(raw: box).replace(with: newValue)
                            \(raw: stubbedBox).replace(with: true)
                        }
                    }
                }
            """)
            resetStubStatements.append("\(raw: box).replace(with: nil)")
            resetStubStatements.append("\(raw: stubbedBox).replace(with: false)")
        }
    } else if isThrowing {
        let box = "__innodi_\(names.thrownErrorProperty)Box"
        members.append("""
            private let \(raw: box) = InnoDITesting.DIConcurrentValueBox<Error?>(nil)
            private let \(raw: stubbedBox) = InnoDITesting.DIConcurrentValueBox(false)
            var \(raw: names.thrownErrorProperty): Error? {
                get { \(raw: state).withCriticalRegion { _ in \(raw: box).snapshot() } }
                set {
                    \(raw: state).withCriticalRegion { _ in
                        \(raw: box).replace(with: newValue)
                        \(raw: stubbedBox).replace(with: true)
                    }
                }
            }
        """)
        resetStubStatements.append("\(raw: box).replace(with: nil)")
        resetStubStatements.append("\(raw: stubbedBox).replace(with: false)")
    }

    let returnFragment = returnsVoid ? "" : " -> \(returnType)"
    let body: CodeBlockItemListSyntax
    if typedFailure != nil {
        let box = "__innodi_\(names.resultProperty)Box"
        body = """
                let \(raw: result) = \(raw: state).withCriticalRegion { \(raw: generation) in
                    \(raw: scope.member(callBox)).update { $0.append(.init(\(initializedRecordArgs))) }
                    return \(raw: scope.member(box)).snapshot()
                }
                guard let \(raw: result) else {
                    preconditionFailure("\(raw: names.resultProperty) was not set on \\(Self.self) before \(raw: baseName) was invoked")
                }
                return try \(raw: result).get()
        """
    } else if !returnsVoid {
        if isThrowing {
            let box = "__innodi_\(names.resultProperty)Box"
            body = """
                    let \(raw: result) = \(raw: state).withCriticalRegion { \(raw: generation) in
                        \(raw: scope.member(callBox)).update { $0.append(.init(\(initializedRecordArgs))) }
                        return \(raw: scope.member(box)).snapshot()
                    }
                    return try \(raw: result).get()
            """
        } else {
            let box = "__innodi_\(names.returnProperty)Box"
            let storedReturn = renderStoredReturn(
                storage: "\(scope.member(box)).snapshot()",
                type: returnType
            )
            body = """
                    return \(raw: state).withCriticalRegion { \(raw: generation) in
                        \(raw: scope.member(callBox)).update { $0.append(.init(\(initializedRecordArgs))) }
                        guard \(raw: scope.member(stubbedBox)).snapshot() else {
                            preconditionFailure("\(raw: names.returnProperty) was not set on \\(Self.self) before \(raw: baseName) was invoked")
                        }
                        \(storedReturn)
                    }
            """
        }
    } else if isThrowing {
        let box = "__innodi_\(names.thrownErrorProperty)Box"
        body = """
                let \(raw: error) = \(raw: state).withCriticalRegion { \(raw: generation) in
                    \(raw: scope.member(callBox)).update { $0.append(.init(\(initializedRecordArgs))) }
                    return \(raw: scope.member(box)).snapshot()
                }
                if let \(raw: error) { throw \(raw: error) }
        """
    } else {
        body = """
                \(raw: state).withCriticalRegion { \(raw: generation) in
                    \(raw: scope.member(callBox)).update { $0.append(.init(\(initializedRecordArgs))) }
                }
        """
    }
    let invocationBody = CodeBlockItemListSyntax(captures + Array(body))
    members.append("""
        func \(raw: baseName)(\(parameterList))\(raw: effectsRendered)\(raw: returnFragment) {
    \(invocationBody)
        }
    """)

    return RenderedFunctionMock(
        members: members,
        usesNotStubbedError: typedFailure == nil && isThrowing && !returnsVoid,
        missingStubExpression: requiresFunctionStub(
            returnsVoid: returnsVoid,
            isThrowing: isThrowing
        ) ? ExprSyntax("!\(raw: scope.member(stubbedBox)).snapshot() ? \(literal: names.stem) : nil") : nil,
        recordedCallCount: recordedCallCountElement(
            stem: names.stem,
            count: "\(raw: callBox).snapshot().count"
        ),
        resetCallStatement: "\(raw: callBox).replace(with: [])",
        resetStubStatements: resetStubStatements
    )
}

private func renderTypedFunctionMock(
    function: FunctionDeclSyntax,
    names: MockFunctionNames,
    stateNames: MockStateNames
) -> RenderedFunctionMock? {
    let scope = MockFunctionScope(function)
    let signature = function.signature
    let isAsync = signature.effectSpecifiers?.asyncSpecifier != nil
    let throwsSpelling = signature.effectSpecifiers?.throwsClause?.trimmedDescription
    let isThrowing = throwsSpelling != nil
    let typedFailure = typedThrowsFailureType(throwsSpelling)

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
    let parameterList = functionParameterList(callParameters)
    var effectSpecifierTokens: [String] = []
    if isAsync { effectSpecifierTokens.append("async") }
    if let throwsSpelling { effectSpecifierTokens.append(throwsSpelling) }
    let effectSpecifiersJoined = effectSpecifierTokens.isEmpty
        ? ""
        : " " + effectSpecifierTokens.joined(separator: " ")

    var resetStubStatements: [CodeBlockItemSyntax] = []
    var members = MockMembers("""
        struct \(raw: names.callStructName) {
            let generation: UInt64\(callFieldMembers(callParameters))
        }
        private(set) var \(raw: names.callsProperty): [\(raw: names.callStructName)] = []
    """)

    let stubbedStorage = "__innodi_\(names.stem)IsStubbed"
    if !returnsVoid {
        members.append("""
            private var \(raw: stubbedStorage) = false
        """)
        if let typedFailure {
            let storage = "__innodi_\(names.resultProperty)Storage"
            let type = "Result<\(returnTypeRendered), \(typedFailure)>?"
            members.append("""
                private var \(raw: storage): \(raw: type)
            """)
            members.append(
                computedStubProperty(
                    name: names.resultProperty,
                    type: type,
                    storage: storage,
                    stubbedStorage: stubbedStorage,
                    nilMeansMissing: true
                )
            )
            resetStubStatements.append("\(raw: storage) = nil")
            resetStubStatements.append("\(raw: stubbedStorage) = false")
        } else if isThrowing {
            // `Result<T, Error>` keeps the typed `throw` lossy but lets the
            // mock author choose between `.success(value)` and `.failure(error)`
            // with a single assignment. The default failure prompts the test
            // author with the missing stub identifier through the nested
            // `_InnoDIMockNotStubbed` error.
            let storage = "__innodi_\(names.resultProperty)Storage"
            members.append("""
                private var \(raw: storage): Result<\(raw: returnTypeRendered), Error> = .failure(\(raw: stateNames.notStubbedError)(selector: \(literal: names.resultProperty)))
            """)
            members.append(
                computedStubProperty(
                    name: names.resultProperty,
                    type: "Result<\(returnTypeRendered), Error>",
                    storage: storage,
                    stubbedStorage: stubbedStorage
                )
            )
            resetStubStatements.append("\(raw: storage) = .failure(\(raw: stateNames.notStubbedError)(selector: \(literal: names.resultProperty)))")
            resetStubStatements.append("\(raw: stubbedStorage) = false")
        } else {
            let storage = "__innodi_\(names.returnProperty)Storage"
            let storageType = optionalStorageType(returnTypeRendered)
            members.append("""
                private var \(raw: storage): \(raw: storageType)
            """)
            members.append(
                computedStubProperty(
                    name: names.returnProperty,
                    type: storageType,
                    storage: storage,
                    stubbedStorage: stubbedStorage
                )
            )
            resetStubStatements.append("\(raw: storage) = nil")
            resetStubStatements.append("\(raw: stubbedStorage) = false")
        }
    } else if let typedFailure {
        let storage = "__innodi_\(names.resultProperty)Storage"
        members.append("""
            private var \(raw: stubbedStorage) = false
            private var \(raw: storage): Result<Void, \(raw: typedFailure)>?
        """)
        members.append(
            computedStubProperty(
                name: names.resultProperty,
                type: "Result<Void, \(typedFailure)>?",
                storage: storage,
                stubbedStorage: stubbedStorage,
                nilMeansMissing: true
            )
        )
        resetStubStatements.append("\(raw: storage) = nil")
        resetStubStatements.append("\(raw: stubbedStorage) = false")
    } else if isThrowing {
        // Even a Void-returning throwing function needs an opt-in error
        // hook so tests can simulate the failure path.
        let storage = "__innodi_\(names.thrownErrorProperty)Storage"
        members.append("""
            private var \(raw: stubbedStorage) = false
            private var \(raw: storage): Error?
        """)
        members.append(
            computedStubProperty(
                name: names.thrownErrorProperty,
                type: "Error?",
                storage: storage,
                stubbedStorage: stubbedStorage
            )
        )
        resetStubStatements.append("\(raw: storage) = nil")
        resetStubStatements.append("\(raw: stubbedStorage) = false")
    }

    let initializedRecordArgs = recordArguments(
        callParameters,
        generation: scope.member(stateNames.generation)
    )
    let returnFragment = returnsVoid ? "" : " -> \(returnTypeRendered)"
    let record: CodeBlockItemListSyntax = """
            \(raw: scope.member(names.callsProperty)).append(.init(\(initializedRecordArgs)))
    """
    let body: CodeBlockItemListSyntax
    if typedFailure != nil {
        body = """
        \(record)
                guard let result = \(raw: scope.member(names.resultProperty)) else {
                    preconditionFailure("\(raw: names.resultProperty) was not set on \\(Self.self) before \(raw: baseName) was invoked")
                }
                return try result.get()
        """
    } else if !returnsVoid {
        if isThrowing {
            body = """
            \(record)
                    return try \(raw: scope.member(names.resultProperty)).get()
            """
        } else {
            let storedReturn = renderStoredReturn(
                storage: scope.member(names.returnProperty),
                type: returnTypeRendered
            )
            body = """
            \(record)
                    guard \(raw: scope.member(stubbedStorage)) else {
                        preconditionFailure("\(raw: names.returnProperty) was not set on \\(Self.self) before \(raw: baseName) was invoked")
                    }
                    \(storedReturn)
            """
        }
    } else if isThrowing {
        body = """
        \(record)
                if let error = \(raw: scope.member(names.thrownErrorProperty)) {
                    throw error
                }
        """
    } else {
        body = record
    }
    members.append("""
        func \(raw: baseName)(\(parameterList))\(raw: effectSpecifiersJoined)\(raw: returnFragment) {
    \(body)
        }
    """)

    return RenderedFunctionMock(
        members: members,
        usesNotStubbedError: typedFailure == nil && isThrowing && !returnsVoid,
        missingStubExpression: requiresFunctionStub(
            returnsVoid: returnsVoid,
            isThrowing: isThrowing
        ) ? ExprSyntax("!\(raw: stubbedStorage) ? \(literal: names.stem) : nil") : nil,
        recordedCallCount: recordedCallCountElement(
            stem: names.stem,
            count: "\(raw: names.callsProperty).count"
        ),
        resetCallStatement: "\(raw: names.callsProperty).removeAll(keepingCapacity: false)",
        resetStubStatements: resetStubStatements
    )
}

private func renderGenericFunctionMock(
    function: FunctionDeclSyntax,
    names: MockFunctionNames,
    stateNames: MockStateNames
) -> RenderedFunctionMock? {
    let scope = MockFunctionScope(function)
    let handler = scope.local("handler")
    let rawValue = scope.local("rawValue")
    let value = scope.local("value")
    let signature = function.signature
    let isAsync = signature.effectSpecifiers?.asyncSpecifier != nil
    let isThrowing = signature.effectSpecifiers?.throwsClause != nil

    let baseName = function.name.text
    let parameters = signature.parameterClause.parameters
    guard let callParameters = renderableCallParameters(parameters, eraseTypes: true) else {
        return nil
    }
    let parameterList = functionParameterList(callParameters)
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
    let handlerArguments = ArrayExprSyntax(
        elements: ArrayElementListSyntax(
            callParameters.enumerated().map { index, parameter in
                ArrayElementSyntax(
                    expression: parameter.argumentExpression,
                    trailingComma: index == callParameters.count - 1
                        ? nil
                        : .commaToken(trailingTrivia: .space)
                )
            }
        )
    )

    let handlerType = "(([Any])\(handlerEffectsJoined) -> \(handlerReturnType))?"
    let handlerStorage = "__innodi_\(names.handlerProperty)Storage"
    let stubbedStorage = "__innodi_\(names.stem)IsStubbed"
    var members = MockMembers("""
        struct \(raw: names.callStructName) {
            let generation: UInt64\(callFieldMembers(callParameters))
        }
        private(set) var \(raw: names.callsProperty): [\(raw: names.callStructName)] = []
        private var \(raw: handlerStorage): \(raw: handlerType)
        private var \(raw: stubbedStorage) = false
    """)
    members.append(
        computedStubProperty(
            name: names.handlerProperty,
            type: handlerType,
            storage: handlerStorage,
            stubbedStorage: stubbedStorage,
            nilMeansMissing: true
        )
    )

    let returnFragment = returnsVoid ? "" : " -> \(returnTypeRendered)"
    let initializedRecordArgs = recordArguments(
        callParameters,
        generation: scope.member(stateNames.generation)
    )
    let body: CodeBlockItemListSyntax
    if returnsVoid {
        body = """
                \(raw: scope.member(names.callsProperty)).append(.init(\(initializedRecordArgs)))
                if let \(raw: handler) = \(raw: scope.member(names.handlerProperty)) {
                    \(raw: invocationPrefix)\(raw: handler)(\(handlerArguments))
                }
        """
    } else {
        body = """
                \(raw: scope.member(names.callsProperty)).append(.init(\(initializedRecordArgs)))
                guard let \(raw: handler) = \(raw: scope.member(names.handlerProperty)) else {
                    preconditionFailure("\(raw: names.handlerProperty) was not set on \\(Self.self) before \(raw: baseName) was invoked")
                }
                let \(raw: rawValue) = \(raw: invocationPrefix)\(raw: handler)(\(handlerArguments))
                guard let \(raw: value) = \(raw: rawValue) as? \(raw: returnTypeRendered) else {
                    preconditionFailure("\(raw: names.handlerProperty) returned a value that cannot be cast to \(raw: returnTypeRendered)")
                }
                return \(raw: value)
        """
    }
    members.append("""
        func \(raw: baseName)\(raw: genericParameterClause)(\(parameterList))\(raw: effectSpecifiersJoined)\(raw: returnFragment)\(raw: genericWhereClause) {
    \(body)
        }
    """)

    return RenderedFunctionMock(
        members: members,
        usesNotStubbedError: false,
        missingStubExpression: "!\(raw: stubbedStorage) ? \(literal: names.stem) : nil",
        recordedCallCount: recordedCallCountElement(
            stem: names.stem,
            count: "\(raw: names.callsProperty).count"
        ),
        resetCallStatement: "\(raw: names.callsProperty).removeAll(keepingCapacity: false)",
        resetStubStatements: [
            "\(raw: handlerStorage) = nil",
            "\(raw: stubbedStorage) = false"
        ]
    )
}

struct RenderedVariableMock {
    let members: MockMembers
    let missingStubExpression: ExprSyntax
    let resetStubStatements: [CodeBlockItemSyntax]
}

func renderVariableMock(
    variable: VariableDeclSyntax,
    concurrent: Bool = false,
    stateNames: MockStateNames = MockStateNames(),
    reserving names: Set<String> = []
) -> RenderedVariableMock? {
    if findStandardMainActorAttribute(in: variable.attributes) != nil {
        return nil
    }
    if unsupportedMockIsolation(in: variable.attributes) != nil {
        return nil
    }
    if !variable.modifiers.isEmpty {
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
    let storageName = freshMockIdentifier(
        "__innodi_\(name.safeLowerCamelIdentifier)_\(name.stableIdentifierSuffix)StubValue",
        reserving: names
    )
    let stubbedName = freshMockIdentifier(
        "__innodi_\(name.safeLowerCamelIdentifier)_\(name.stableIdentifierSuffix)IsStubbed",
        reserving: names
    )
    let storageType = optionalStorageType(type)
    if concurrent {
        let boxName = freshMockIdentifier("\(storageName)Box", reserving: names)
        let stubbedBoxName = freshMockIdentifier("\(stubbedName)Box", reserving: names)
        let storedReturn = renderStoredReturn(storage: "\(boxName).snapshot()", type: type)
        return RenderedVariableMock(
            members: MockMembers("""
            private let \(raw: boxName) = InnoDITesting.DIConcurrentValueBox<\(raw: storageType)>(nil)
            private let \(raw: stubbedBoxName) = InnoDITesting.DIConcurrentValueBox(false)
            var \(raw: escapedName): \(raw: type) {
                get {
                    return \(raw: stateNames.concurrentState).withCriticalRegion { _ in
                        guard \(raw: stubbedBoxName).snapshot() else {
                            preconditionFailure("\(raw: name) was not set on \\(Self.self) before it was read")
                        }
                        \(storedReturn)
                    }
                }
                set {
                    \(raw: stateNames.concurrentState).withCriticalRegion { _ in
                        \(raw: boxName).replace(with: newValue)
                        \(raw: stubbedBoxName).replace(with: true)
                    }
                }
            }
            """),
            missingStubExpression:
                "!\(raw: stubbedBoxName).snapshot() ? \(literal: name) : nil",
            resetStubStatements: [
                "\(raw: boxName).replace(with: nil)",
                "\(raw: stubbedBoxName).replace(with: false)"
            ]
        )
    }
    let storedReturn = renderStoredReturn(storage: storageName, type: type)
    return RenderedVariableMock(
        members: MockMembers("""
            private var \(raw: storageName): \(raw: storageType)
            private var \(raw: stubbedName) = false
            var \(raw: escapedName): \(raw: type) {
                get {
                    guard \(raw: stubbedName) else {
                        preconditionFailure("\(raw: name) was not set on \\(Self.self) before it was read")
                    }
                    \(storedReturn)
                }
                set {
                    \(raw: storageName) = newValue
                    \(raw: stubbedName) = true
                }
            }
        """),
        missingStubExpression: "!\(raw: stubbedName) ? \(literal: name) : nil",
        resetStubStatements: [
            "\(raw: storageName) = nil",
            "\(raw: stubbedName) = false"
        ]
    )
}

private struct RenderableCallParameter {
    let fieldLabel: String
    let fieldIdentifier: String
    var argumentIdentifier: String
    let type: String
    let declaration: FunctionParameterSyntax
    var requiresCopy: Bool

    var argumentExpression: ExprSyntax {
        if requiresCopy {
            return "copy \(raw: argumentIdentifier)"
        }
        return ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(argumentIdentifier)))
    }
}

private func renderableCallParameters(
    _ parameters: FunctionParameterListSyntax,
    eraseTypes: Bool = false
) -> [RenderableCallParameter]? {
    let originalFieldNames = Set(parameters.compactMap { parameter -> String? in
        let name = (parameter.secondName ?? parameter.firstName).text.unescapedIdentifier
        return name == "_" ? nil : name.safeLowerCamelIdentifier
    })
    var usedFieldNames: Set<String> = ["generation"]
    var usedArgumentNames = Set(parameters.map {
        ($0.secondName ?? $0.firstName).text.unescapedIdentifier
    })
    var rendered: [RenderableCallParameter] = []
    for (index, parameter) in parameters.enumerated() {
        let internalName = (parameter.secondName?.text ?? parameter.firstName.text)
        let baseFieldName = internalName == "_"
            ? "value\(index + 1)"
            : internalName.unescapedIdentifier.safeLowerCamelIdentifier
        let reservedFieldNames = usedFieldNames.union(
            internalName == "_" ? originalFieldNames : originalFieldNames.subtracting([baseFieldName])
        )
        let unescapedFieldName = freshMockIdentifier(baseFieldName, reserving: reservedFieldNames)
        usedFieldNames.insert(unescapedFieldName)
        guard let typeText = renderableCallRecordType(parameter, eraseTypes: eraseTypes) else {
            return nil
        }
        let argumentName: String
        let declaration: FunctionParameterSyntax
        let parameterWithoutComma = parameter.with(\.trailingComma, nil)
        if internalName == "_" {
            let synthesizedName = freshMockIdentifier(unescapedFieldName, reserving: usedArgumentNames)
            usedArgumentNames.insert(synthesizedName)
            argumentName = synthesizedName.escapedSwiftIdentifier
            declaration = parameterWithoutComma
                .with(
                    \.secondName,
                    .identifier(synthesizedName, leadingTrivia: .space)
                )
                .trimmed
        } else {
            argumentName = internalName.unescapedIdentifier.escapedSwiftIdentifier
            declaration = parameterWithoutComma.trimmed
        }
        rendered.append(
            RenderableCallParameter(
                fieldLabel: unescapedFieldName,
                fieldIdentifier: unescapedFieldName.escapedSwiftIdentifier,
                argumentIdentifier: argumentName,
                type: typeText,
                declaration: declaration,
                requiresCopy: mockParameterSpecifiers(parameter.type).contains {
                    ["consuming", "borrowing", "__owned", "__shared"].contains($0)
                }
            )
        )
    }
    return rendered
}

private func requiresFunctionStub(
    returnsVoid: Bool,
    isThrowing: Bool
) -> Bool {
    !returnsVoid || isThrowing
}

/// The mock method's parameters, separated like the requirement's.
private func functionParameterList(
    _ parameters: [RenderableCallParameter]
) -> FunctionParameterListSyntax {
    FunctionParameterListSyntax(
        parameters.enumerated().map { index, parameter in
            parameter.declaration.with(
                \.trailingComma,
                index == parameters.count - 1 ? nil : .commaToken(trailingTrivia: .space)
            )
        }
    )
}

/// `generation: <generation>, <field>: <argument>, ...` for one call record.
private func recordArguments(
    _ parameters: [RenderableCallParameter],
    generation: String
) -> LabeledExprListSyntax {
    let arguments = [(label: "generation", value: ExprSyntax("\(raw: generation)"))]
        + parameters.map { (label: $0.fieldLabel, value: $0.argumentExpression) }
    return LabeledExprListSyntax(
        arguments.enumerated().map { index, argument in
            LabeledExprSyntax(
                label: .identifier(argument.label),
                colon: .colonToken(trailingTrivia: .space),
                expression: argument.value,
                trailingComma: index == arguments.count - 1
                    ? nil
                    : .commaToken(trailingTrivia: .space)
            )
        }
    )
}

/// The `let <field>: <type>` members of a call record, one per line.
private func callFieldMembers(
    _ parameters: [RenderableCallParameter]
) -> MemberBlockItemListSyntax {
    MemberBlockItemListSyntax(
        parameters.map { parameter in
            MemberBlockItemSyntax(
                leadingTrivia: .newline + .spaces(8),
                decl: "let \(raw: parameter.fieldIdentifier): \(raw: parameter.type)" as DeclSyntax
            )
        }
    )
}

/// The `"<stem>": <count>` entry that reports a requirement's call count.
private func recordedCallCountElement(
    stem: String,
    count: ExprSyntax
) -> DictionaryElementSyntax {
    DictionaryElementSyntax(
        key: StringLiteralExprSyntax(content: stem),
        colon: .colonToken(trailingTrivia: .space),
        value: count
    )
}

private func computedStubProperty(
    name: String,
    type: String,
    storage: String,
    stubbedStorage: String,
    nilMeansMissing: Bool = false
) -> MemberBlockItemListSyntax {
    let stateUpdate = nilMeansMissing ? "newValue != nil" : "true"
    return """
        var \(raw: name): \(raw: type) {
            get { \(raw: storage) }
            set {
                \(raw: storage) = newValue
                \(raw: stubbedStorage) = \(raw: stateUpdate)
            }
        }
    """
}

/// Returns the stored stub. Typed interpolation indents every line of it to
/// the line it lands on.
private func renderStoredReturn(storage: String, type: String) -> CodeBlockItemListSyntax {
    if type.hasSuffix("?") || type.hasSuffix("!") {
        return "return \(raw: storage) ?? nil"
    }
    return """
        guard let value = \(raw: storage) else {
            preconditionFailure("Stub storage for \(raw: type) was unexpectedly empty")
        }
        return value
        """
}

private func renderableCallRecordType(
    _ parameter: FunctionParameterSyntax,
    eraseTypes: Bool
) -> String? {
    if mockParameterSpecifiers(parameter.type).contains("inout") {
        return nil
    }
    if eraseTypes {
        return "Any"
    }
    if isOpaqueType(parameter.type.trimmedDescription) {
        return nil
    }

    let storedType = mockCallRecordType(parameter.type).trimmed
    if parameter.ellipsis != nil {
        return ArrayTypeSyntax(element: storedType).trimmedDescription
    }
    return storedType.trimmedDescription
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
    let spelling = throwsClause.trimmedDescription
    return spelling != "throws" && typedThrowsFailureType(spelling) == nil
}

private func typedThrowsFailureType(_ spelling: String?) -> String? {
    guard let spelling,
          spelling.hasPrefix("throws("),
          spelling.hasSuffix(")") else {
        return nil
    }
    let start = spelling.index(spelling.startIndex, offsetBy: 7)
    let end = spelling.index(before: spelling.endIndex)
    let failure = spelling[start..<end]
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return failure.isEmpty ? nil : failure
}

private func isOpaqueType(_ typeText: String) -> Bool {
    typeText == "some" || typeText.hasPrefix("some ") || typeText.contains(" some ")
}

func isVoidReturnType(_ typeText: String?) -> Bool {
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
