
protocol Formatter {
    func format(_ value: Int) -> String
    func format(_ value: Double) -> String
    func format(_ value: Int, width: Int) throws -> String
}

/// Auto-generated mock for `Formatter` (RFC 0001 stage 2).
final class FormatterMock: Formatter {
    init() {
    }

    private var __innodiMockGeneration: UInt64 = 0

    struct _InnoDIMockNotStubbed: Error, CustomStringConvertible {
        let selector: String
        var description: String {
            "InnoDI mock selector '\(selector)' was not stubbed before invocation."
        }
    }

    struct FormatUnlabeledIntCall {
        let generation: UInt64
        let value: Int
    }
    private(set) var formatUnlabeledIntCalls: [FormatUnlabeledIntCall] = []
    private var __innodi_formatUnlabeledIntIsStubbed = false
    private var __innodi_formatUnlabeledIntReturnValueStorage: String?
    var formatUnlabeledIntReturnValue: String? {
        get {
            __innodi_formatUnlabeledIntReturnValueStorage
        }
        set {
            __innodi_formatUnlabeledIntReturnValueStorage = newValue
            __innodi_formatUnlabeledIntIsStubbed = true
        }
    }
    func format(_ value: Int) -> String {
        formatUnlabeledIntCalls.append(.init(generation: __innodiMockGeneration, value: value))
        guard __innodi_formatUnlabeledIntIsStubbed else {
            preconditionFailure("formatUnlabeledIntReturnValue was not set on \(Self.self) before format was invoked")
        }
        guard let value = formatUnlabeledIntReturnValue else {
            preconditionFailure("Stub storage for String was unexpectedly empty")
        }
        return value
    }

    struct FormatUnlabeledDoubleCall {
        let generation: UInt64
        let value: Double
    }
    private(set) var formatUnlabeledDoubleCalls: [FormatUnlabeledDoubleCall] = []
    private var __innodi_formatUnlabeledDoubleIsStubbed = false
    private var __innodi_formatUnlabeledDoubleReturnValueStorage: String?
    var formatUnlabeledDoubleReturnValue: String? {
        get {
            __innodi_formatUnlabeledDoubleReturnValueStorage
        }
        set {
            __innodi_formatUnlabeledDoubleReturnValueStorage = newValue
            __innodi_formatUnlabeledDoubleIsStubbed = true
        }
    }
    func format(_ value: Double) -> String {
        formatUnlabeledDoubleCalls.append(.init(generation: __innodiMockGeneration, value: value))
        guard __innodi_formatUnlabeledDoubleIsStubbed else {
            preconditionFailure("formatUnlabeledDoubleReturnValue was not set on \(Self.self) before format was invoked")
        }
        guard let value = formatUnlabeledDoubleReturnValue else {
            preconditionFailure("Stub storage for String was unexpectedly empty")
        }
        return value
    }

    struct FormatUnlabeledIntWidthIntCall {
        let generation: UInt64
        let value: Int
        let width: Int
    }
    private(set) var formatUnlabeledIntWidthIntCalls: [FormatUnlabeledIntWidthIntCall] = []
    private var __innodi_formatUnlabeledIntWidthIntIsStubbed = false
    private var __innodi_formatUnlabeledIntWidthIntResultStorage: Result<String, Error> = .failure(_InnoDIMockNotStubbed(selector: "formatUnlabeledIntWidthIntResult"))
    var formatUnlabeledIntWidthIntResult: Result<String, Error> {
        get {
            __innodi_formatUnlabeledIntWidthIntResultStorage
        }
        set {
            __innodi_formatUnlabeledIntWidthIntResultStorage = newValue
            __innodi_formatUnlabeledIntWidthIntIsStubbed = true
        }
    }
    func format(_ value: Int, width: Int) throws -> String {
        formatUnlabeledIntWidthIntCalls.append(.init(generation: __innodiMockGeneration, value: value, width: width))
        return try formatUnlabeledIntWidthIntResult.get()
    }

    var missingStubSelectors: [String] {
        [
            !__innodi_formatUnlabeledIntIsStubbed ? "formatUnlabeledInt" : nil,
            !__innodi_formatUnlabeledDoubleIsStubbed ? "formatUnlabeledDouble" : nil,
            !__innodi_formatUnlabeledIntWidthIntIsStubbed ? "formatUnlabeledIntWidthInt" : nil
        ].compactMap {
            $0
        }
    }

    var recordedCallCounts: [String: Int] {
        [
            "formatUnlabeledInt": formatUnlabeledIntCalls.count,
            "formatUnlabeledDouble": formatUnlabeledDoubleCalls.count,
            "formatUnlabeledIntWidthInt": formatUnlabeledIntWidthIntCalls.count
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
                "formatUnlabeledInt": formatUnlabeledIntCalls.count,
                "formatUnlabeledDouble": formatUnlabeledDoubleCalls.count,
                "formatUnlabeledIntWidthInt": formatUnlabeledIntWidthIntCalls.count
            ]
        )
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        let snapshot = innoDICallHistorySnapshot
        formatUnlabeledIntCalls.removeAll(keepingCapacity: false)
        formatUnlabeledDoubleCalls.removeAll(keepingCapacity: false)
        formatUnlabeledIntWidthIntCalls.removeAll(keepingCapacity: false)
        if scope == .all {
            __innodi_formatUnlabeledIntReturnValueStorage = nil
            __innodi_formatUnlabeledIntIsStubbed = false
            __innodi_formatUnlabeledDoubleReturnValueStorage = nil
            __innodi_formatUnlabeledDoubleIsStubbed = false
            __innodi_formatUnlabeledIntWidthIntResultStorage = .failure(_InnoDIMockNotStubbed(selector: "formatUnlabeledIntWidthIntResult"))
            __innodi_formatUnlabeledIntWidthIntIsStubbed = false
        }
        __innodiMockGeneration &+= 1
        return snapshot
    }
}