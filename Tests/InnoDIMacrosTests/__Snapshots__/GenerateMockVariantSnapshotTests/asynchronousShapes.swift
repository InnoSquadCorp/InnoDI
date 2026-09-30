
protocol Loader {
    func load(path: String) async -> Data
    func warmUp() async
}

/// Auto-generated mock for `Loader` (RFC 0001 stage 2).
final class LoaderMock: Loader {
    init() {
    }

    private var __innodiMockGeneration: UInt64 = 0

    struct LoadCall {
        let generation: UInt64
        let path: String
    }
    private(set) var loadCalls: [LoadCall] = []
    private var __innodi_loadIsStubbed = false
    private var __innodi_loadReturnValueStorage: Data?
    var loadReturnValue: Data? {
        get {
            __innodi_loadReturnValueStorage
        }
        set {
            __innodi_loadReturnValueStorage = newValue
            __innodi_loadIsStubbed = true
        }
    }
    func load(path: String) async -> Data {
        loadCalls.append(.init(generation: __innodiMockGeneration, path: path))
        guard __innodi_loadIsStubbed else {
            preconditionFailure("loadReturnValue was not set on \(Self.self) before load was invoked")
        }
        guard let value = loadReturnValue else {
            preconditionFailure("Stub storage for Data was unexpectedly empty")
        }
        return value
    }

    struct WarmUpCall {
        let generation: UInt64
    }
    private(set) var warmUpCalls: [WarmUpCall] = []
    func warmUp() async {
        warmUpCalls.append(.init(generation: __innodiMockGeneration))
    }

    var missingStubSelectors: [String] {
        [
            !__innodi_loadIsStubbed ? "load" : nil
        ].compactMap {
            $0
        }
    }

    var recordedCallCounts: [String: Int] {
        [
            "load": loadCalls.count,
            "warmUp": warmUpCalls.count
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
                "load": loadCalls.count,
                "warmUp": warmUpCalls.count
            ]
        )
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        let snapshot = innoDICallHistorySnapshot
        loadCalls.removeAll(keepingCapacity: false)
        warmUpCalls.removeAll(keepingCapacity: false)
        if scope == .all {
            __innodi_loadReturnValueStorage = nil
            __innodi_loadIsStubbed = false
        }
        __innodiMockGeneration &+= 1
        return snapshot
    }
}