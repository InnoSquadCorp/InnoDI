enum LoadFailure: Error { case missing 
}
protocol Parser {
    func parse(_ text: String) throws -> Int
    func validate(_ text: String) throws
    func decode(_ text: String) throws(LoadFailure) -> Int
    func check(_ text: String) async throws(LoadFailure)
}

/// Auto-generated mock for `Parser` (RFC 0001 stage 2).
final class ParserMock: Parser {
    init() {
    }

    private var __innodiMockGeneration: UInt64 = 0

    struct _InnoDIMockNotStubbed: Error, CustomStringConvertible {
        let selector: String
        var description: String {
            "InnoDI mock selector '\(selector)' was not stubbed before invocation."
        }
    }

    struct ParseCall {
        let generation: UInt64
        let text: String
    }
    private(set) var parseCalls: [ParseCall] = []
    private var __innodi_parseIsStubbed = false
    private var __innodi_parseResultStorage: Result<Int, Error> = .failure(_InnoDIMockNotStubbed(selector: "parseResult"))
    var parseResult: Result<Int, Error> {
        get {
            __innodi_parseResultStorage
        }
        set {
            __innodi_parseResultStorage = newValue
            __innodi_parseIsStubbed = true
        }
    }
    func parse(_ text: String) throws -> Int {
        parseCalls.append(.init(generation: __innodiMockGeneration, text: text))
        return try parseResult.get()
    }

    struct ValidateCall {
        let generation: UInt64
        let text: String
    }
    private(set) var validateCalls: [ValidateCall] = []
    private var __innodi_validateIsStubbed = false
    private var __innodi_validateThrownErrorStorage: Error?
    var validateThrownError: Error? {
        get {
            __innodi_validateThrownErrorStorage
        }
        set {
            __innodi_validateThrownErrorStorage = newValue
            __innodi_validateIsStubbed = true
        }
    }
    func validate(_ text: String) throws {
        validateCalls.append(.init(generation: __innodiMockGeneration, text: text))
        if let error = validateThrownError {
            throw error
        }
    }

    struct DecodeCall {
        let generation: UInt64
        let text: String
    }
    private(set) var decodeCalls: [DecodeCall] = []
    private var __innodi_decodeIsStubbed = false
    private var __innodi_decodeResultStorage: Result<Int, LoadFailure>?
    var decodeResult: Result<Int, LoadFailure>? {
        get {
            __innodi_decodeResultStorage
        }
        set {
            __innodi_decodeResultStorage = newValue
            __innodi_decodeIsStubbed = newValue != nil
        }
    }
    func decode(_ text: String) throws(LoadFailure) -> Int {
        decodeCalls.append(.init(generation: __innodiMockGeneration, text: text))
        guard let result = decodeResult else {
            preconditionFailure("decodeResult was not set on \(Self.self) before decode was invoked")
        }
        return try result.get()
    }

    struct CheckCall {
        let generation: UInt64
        let text: String
    }
    private(set) var checkCalls: [CheckCall] = []
    private var __innodi_checkIsStubbed = false
    private var __innodi_checkResultStorage: Result<Void, LoadFailure>?
    var checkResult: Result<Void, LoadFailure>? {
        get {
            __innodi_checkResultStorage
        }
        set {
            __innodi_checkResultStorage = newValue
            __innodi_checkIsStubbed = newValue != nil
        }
    }
    func check(_ text: String) async throws(LoadFailure) {
        checkCalls.append(.init(generation: __innodiMockGeneration, text: text))
        guard let result = checkResult else {
            preconditionFailure("checkResult was not set on \(Self.self) before check was invoked")
        }
        return try result.get()
    }

    var missingStubSelectors: [String] {
        [
            !__innodi_parseIsStubbed ? "parse" : nil,
            !__innodi_validateIsStubbed ? "validate" : nil,
            !__innodi_decodeIsStubbed ? "decode" : nil,
            !__innodi_checkIsStubbed ? "check" : nil
        ].compactMap {
            $0
        }
    }

    var recordedCallCounts: [String: Int] {
        [
            "parse": parseCalls.count,
            "validate": validateCalls.count,
            "decode": decodeCalls.count,
            "check": checkCalls.count
        ]
    }

    enum InnoDIResetScope: Sendable {
        case calls
        case all
    }

    struct InnoDICallHistorySnapshot: Equatable, Sendable {
        let generation: UInt64
        let recordedCallCounts: [String: Int]
    }

    var innoDICallHistoryGeneration: UInt64 {
        __innodiMockGeneration
    }

    var innoDICallHistorySnapshot: InnoDICallHistorySnapshot {
        .init(
            generation: __innodiMockGeneration,
            recordedCallCounts: [
                "parse": parseCalls.count,
                "validate": validateCalls.count,
                "decode": decodeCalls.count,
                "check": checkCalls.count
            ]
        )
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        let snapshot = innoDICallHistorySnapshot
        parseCalls.removeAll(keepingCapacity: false)
        validateCalls.removeAll(keepingCapacity: false)
        decodeCalls.removeAll(keepingCapacity: false)
        checkCalls.removeAll(keepingCapacity: false)
        if scope == .all {
            __innodi_parseResultStorage = .failure(_InnoDIMockNotStubbed(selector: "parseResult"))
            __innodi_parseIsStubbed = false
            __innodi_validateThrownErrorStorage = nil
            __innodi_validateIsStubbed = false
            __innodi_decodeResultStorage = nil
            __innodi_decodeIsStubbed = false
            __innodi_checkResultStorage = nil
            __innodi_checkIsStubbed = false
        }
        __innodiMockGeneration &+= 1
        return snapshot
    }
}