
protocol Store {
    func value<Value: Decodable>(for key: String, as type: Value.Type) -> Value
    func save<Value>(_ value: Value, for key: String) async throws where Value: Encodable
}

/// Auto-generated mock for `Store` (RFC 0001 stage 2).
final class StoreMock: Store {
    init() {
    }

    private var __innodiMockGeneration: UInt64 = 0

    struct ValueForStringAsValueTypeCall {
        let generation: UInt64
        let key: Any
        let type: Any
    }
    private(set) var valueForStringAsValueTypeCalls: [ValueForStringAsValueTypeCall] = []
    private var __innodi_valueForStringAsValueTypeHandlerStorage: (([Any]) -> Any)?
    private var __innodi_valueForStringAsValueTypeIsStubbed = false
    var valueForStringAsValueTypeHandler: (([Any]) -> Any)? {
        get {
            __innodi_valueForStringAsValueTypeHandlerStorage
        }
        set {
            __innodi_valueForStringAsValueTypeHandlerStorage = newValue
            __innodi_valueForStringAsValueTypeIsStubbed = newValue != nil
        }
    }
    func value<Value: Decodable>(for key: String, as type: Value.Type) -> Value {
        valueForStringAsValueTypeCalls.append(.init(generation: __innodiMockGeneration, key: key, type: type))
        guard let handler = valueForStringAsValueTypeHandler else {
            preconditionFailure("valueForStringAsValueTypeHandler was not set on \(Self.self) before value was invoked")
        }
        let rawValue = handler([key, type])
        guard let value = rawValue as? Value else {
            preconditionFailure("valueForStringAsValueTypeHandler returned a value that cannot be cast to Value")
        }
        return value
    }

    struct SaveUnlabeledValueForStringCall {
        let generation: UInt64
        let value: Any
        let key: Any
    }
    private(set) var saveUnlabeledValueForStringCalls: [SaveUnlabeledValueForStringCall] = []
    private var __innodi_saveUnlabeledValueForStringHandlerStorage: (([Any]) async throws -> Void)?
    private var __innodi_saveUnlabeledValueForStringIsStubbed = false
    var saveUnlabeledValueForStringHandler: (([Any]) async throws -> Void)? {
        get {
            __innodi_saveUnlabeledValueForStringHandlerStorage
        }
        set {
            __innodi_saveUnlabeledValueForStringHandlerStorage = newValue
            __innodi_saveUnlabeledValueForStringIsStubbed = newValue != nil
        }
    }
    func save<Value>(_ value: Value, for key: String) async throws where Value: Encodable {
        saveUnlabeledValueForStringCalls.append(.init(generation: __innodiMockGeneration, value: value, key: key))
        if let handler = saveUnlabeledValueForStringHandler {
            try await handler([value, key])
        }
    }

    var missingStubSelectors: [String] {
        [
            !__innodi_valueForStringAsValueTypeIsStubbed ? "valueForStringAsValueType" : nil,
            !__innodi_saveUnlabeledValueForStringIsStubbed ? "saveUnlabeledValueForString" : nil
        ].compactMap {
            $0
        }
    }

    var recordedCallCounts: [String: Int] {
        [
            "valueForStringAsValueType": valueForStringAsValueTypeCalls.count,
            "saveUnlabeledValueForString": saveUnlabeledValueForStringCalls.count
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
                "valueForStringAsValueType": valueForStringAsValueTypeCalls.count,
                "saveUnlabeledValueForString": saveUnlabeledValueForStringCalls.count
            ]
        )
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        let snapshot = innoDICallHistorySnapshot
        valueForStringAsValueTypeCalls.removeAll(keepingCapacity: false)
        saveUnlabeledValueForStringCalls.removeAll(keepingCapacity: false)
        if scope == .all {
            __innodi_valueForStringAsValueTypeHandlerStorage = nil
            __innodi_valueForStringAsValueTypeIsStubbed = false
            __innodi_saveUnlabeledValueForStringHandlerStorage = nil
            __innodi_saveUnlabeledValueForStringIsStubbed = false
        }
        __innodiMockGeneration &+= 1
        return snapshot
    }
}