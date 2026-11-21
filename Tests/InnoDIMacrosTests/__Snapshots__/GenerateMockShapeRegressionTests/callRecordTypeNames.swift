
protocol ToolRunner {
    func tool(named name: String) -> ToolCall
    func start(_ call: StartCall)
    func fetch()
    func log(_ entry: FetchCall.Kind)
    func scoped<LoadCall>(_ value: LoadCall)
    func load()
}

/// Auto-generated mock for `ToolRunner` (RFC 0001 stage 2).
final class ToolRunnerMock: ToolRunner {
    init() {
    }

    private var __innodiMockGeneration: UInt64 = 0

    struct ToolCall2 {
        let generation: UInt64
        let name: String
    }
    private(set) var toolCalls: [ToolCall2] = []
    private var __innodi_toolIsStubbed = false
    private var __innodi_toolReturnValueStorage: ToolCall?
    var toolReturnValue: ToolCall? {
        get {
            __innodi_toolReturnValueStorage
        }
        set {
            __innodi_toolReturnValueStorage = newValue
            __innodi_toolIsStubbed = newValue != nil
        }
    }
    func tool(named name: String) -> ToolCall {
        toolCalls.append(.init(generation: __innodiMockGeneration, name: name))
        guard __innodi_toolIsStubbed else {
            preconditionFailure("toolReturnValue was not set on \(Self.self) before tool was invoked")
        }
        guard let value = toolReturnValue else {
            preconditionFailure("Stub storage for ToolCall was unexpectedly empty")
        }
        return value
    }

    struct StartCall2 {
        let generation: UInt64
        let call: StartCall
    }
    private(set) var startCalls: [StartCall2] = []
    func start(_ call: StartCall) {
        startCalls.append(.init(generation: __innodiMockGeneration, call: call))
    }

    struct FetchCall2 {
        let generation: UInt64
    }
    private(set) var fetchCalls: [FetchCall2] = []
    func fetch() {
        fetchCalls.append(.init(generation: __innodiMockGeneration))
    }

    struct LogCall {
        let generation: UInt64
        let entry: FetchCall.Kind
    }
    private(set) var logCalls: [LogCall] = []
    func log(_ entry: FetchCall.Kind) {
        logCalls.append(.init(generation: __innodiMockGeneration, entry: entry))
    }

    struct ScopedUnlabeledLoadCallCall {
        let generation: UInt64
        let value: Any
    }
    private(set) var scopedUnlabeledLoadCallCalls: [ScopedUnlabeledLoadCallCall] = []
    private var __innodi_scopedUnlabeledLoadCallHandlerStorage: (([Any]) -> Void)?
    private var __innodi_scopedUnlabeledLoadCallIsStubbed = false
    var scopedUnlabeledLoadCallHandler: (([Any]) -> Void)? {
        get {
            __innodi_scopedUnlabeledLoadCallHandlerStorage
        }
        set {
            __innodi_scopedUnlabeledLoadCallHandlerStorage = newValue
            __innodi_scopedUnlabeledLoadCallIsStubbed = newValue != nil
        }
    }
    func scoped<LoadCall>(_ value: LoadCall) {
        scopedUnlabeledLoadCallCalls.append(.init(generation: __innodiMockGeneration, value: value))
        if let handler = scopedUnlabeledLoadCallHandler {
            handler([value])
        }
    }

    struct LoadCall {
        let generation: UInt64
    }
    private(set) var loadCalls: [LoadCall] = []
    func load() {
        loadCalls.append(.init(generation: __innodiMockGeneration))
    }

    var missingStubSelectors: [String] {
        [
            !__innodi_toolIsStubbed ? "tool" : nil,
            !__innodi_scopedUnlabeledLoadCallIsStubbed ? "scopedUnlabeledLoadCall" : nil
        ].compactMap {
            $0
        }
    }

    var recordedCallCounts: [String: Int] {
        [
            "tool": toolCalls.count,
            "start": startCalls.count,
            "fetch": fetchCalls.count,
            "log": logCalls.count,
            "scopedUnlabeledLoadCall": scopedUnlabeledLoadCallCalls.count,
            "load": loadCalls.count
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
                "tool": toolCalls.count,
                "start": startCalls.count,
                "fetch": fetchCalls.count,
                "log": logCalls.count,
                "scopedUnlabeledLoadCall": scopedUnlabeledLoadCallCalls.count,
                "load": loadCalls.count
            ]
        )
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        let snapshot = innoDICallHistorySnapshot
        toolCalls.removeAll(keepingCapacity: false)
        startCalls.removeAll(keepingCapacity: false)
        fetchCalls.removeAll(keepingCapacity: false)
        logCalls.removeAll(keepingCapacity: false)
        scopedUnlabeledLoadCallCalls.removeAll(keepingCapacity: false)
        loadCalls.removeAll(keepingCapacity: false)
        if scope == .all {
            __innodi_toolReturnValueStorage = nil
            __innodi_toolIsStubbed = false
            __innodi_scopedUnlabeledLoadCallHandlerStorage = nil
            __innodi_scopedUnlabeledLoadCallIsStubbed = false
        }
        __innodiMockGeneration &+= 1
        return snapshot
    }
}
protocol ToolInvocations {
    func tool(named name: String) -> ToolInvocation
}

/// Auto-generated mock for `ToolInvocations` (RFC 0001 stage 2).
final class ToolInvocationsMock: ToolInvocations {
    init() {
    }

    private var __innodiMockGeneration: UInt64 = 0

    struct ToolCall {
        let generation: UInt64
        let name: String
    }
    private(set) var toolCalls: [ToolCall] = []
    private var __innodi_toolIsStubbed = false
    private var __innodi_toolReturnValueStorage: ToolInvocation?
    var toolReturnValue: ToolInvocation? {
        get {
            __innodi_toolReturnValueStorage
        }
        set {
            __innodi_toolReturnValueStorage = newValue
            __innodi_toolIsStubbed = newValue != nil
        }
    }
    func tool(named name: String) -> ToolInvocation {
        toolCalls.append(.init(generation: __innodiMockGeneration, name: name))
        guard __innodi_toolIsStubbed else {
            preconditionFailure("toolReturnValue was not set on \(Self.self) before tool was invoked")
        }
        guard let value = toolReturnValue else {
            preconditionFailure("Stub storage for ToolInvocation was unexpectedly empty")
        }
        return value
    }

    var missingStubSelectors: [String] {
        [
            !__innodi_toolIsStubbed ? "tool" : nil
        ].compactMap {
            $0
        }
    }

    var recordedCallCounts: [String: Int] {
        [
            "tool": toolCalls.count
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
                "tool": toolCalls.count
            ]
        )
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        let snapshot = innoDICallHistorySnapshot
        toolCalls.removeAll(keepingCapacity: false)
        if scope == .all {
            __innodi_toolReturnValueStorage = nil
            __innodi_toolIsStubbed = false
        }
        __innodiMockGeneration &+= 1
        return snapshot
    }
}