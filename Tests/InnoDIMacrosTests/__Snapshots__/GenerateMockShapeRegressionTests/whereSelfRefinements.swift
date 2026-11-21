
protocol WhereShared where Self: Sendable {
    func ping() -> Int
}

/// Auto-generated mock for `WhereShared` (RFC 0001 stage 2).
final class WhereSharedMock: WhereShared {
    init() {
    }

    private let __innodiMockState = InnoDITesting.DIConcurrentMockState()

    struct PingCall: Sendable {
        let generation: UInt64
    }
    private let __innodi_pingCallsBox = InnoDITesting.DIConcurrentValueBox<[PingCall]>([])
    var pingCalls: [PingCall] {
        __innodiMockState.withCriticalRegion { _ in
            __innodi_pingCallsBox.snapshot()
        }
    }
    private let __innodi_pingReturnValueBox = InnoDITesting.DIConcurrentValueBox<Int?>(nil)
    private let __innodi_pingStubbedBox = InnoDITesting.DIConcurrentValueBox(false)
    var pingReturnValue: Int? {
        get {
            __innodiMockState.withCriticalRegion { _ in
                __innodi_pingReturnValueBox.snapshot()
            }
        }
        set {
            __innodiMockState.withCriticalRegion { _ in
                __innodi_pingReturnValueBox.replace(with: newValue)
                __innodi_pingStubbedBox.replace(with: newValue != nil)
            }
        }
    }
    func ping() -> Int {
        return __innodiMockState.withCriticalRegion { generation in
            __innodi_pingCallsBox.update {
                $0.append(.init(generation: generation))
            }
            guard __innodi_pingStubbedBox.snapshot() else {
                preconditionFailure("pingReturnValue was not set on \(Self.self) before ping was invoked")
            }
            guard let value = __innodi_pingReturnValueBox.snapshot() else {
                preconditionFailure("Stub storage for Int was unexpectedly empty")
            }
            return value
        }
    }

    var missingStubSelectors: [String] {
        __innodiMockState.withCriticalRegion { _ in
            [
                !__innodi_pingStubbedBox.snapshot() ? "ping" : nil
            ].compactMap {
                $0
            }
        }
    }

    var recordedCallCounts: [String: Int] {
        __innodiMockState.withCriticalRegion { _ in
            [
                "ping": __innodi_pingCallsBox.snapshot().count
            ]
        }
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
        __innodiMockState.withCriticalRegion {
            $0
        }
    }

    var innoDICallHistorySnapshot: InnoDICallHistorySnapshot {
        __innodiMockState.withCriticalRegion { generation in
            .init(
                generation: generation,
                recordedCallCounts: [
                "ping": __innodi_pingCallsBox.snapshot().count
                ]
            )
        }
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        __innodiMockState.reset { generation in
            let snapshot: InnoDICallHistorySnapshot = .init(
                generation: generation,
                recordedCallCounts: [
                "ping": __innodi_pingCallsBox.snapshot().count
                ]
            )
            __innodi_pingCallsBox.replace(with: [])
            if scope == .all {
                __innodi_pingReturnValueBox.replace(with: nil)
                __innodi_pingStubbedBox.replace(with: false)
            }
            return snapshot
        }
    }
}
protocol WhereClassBound where Self: AnyObject {
    func ping() -> Int
}

/// Auto-generated mock for `WhereClassBound` (RFC 0001 stage 2).
final class WhereClassBoundMock: WhereClassBound {
    init() {
    }

    private var __innodiMockGeneration: UInt64 = 0

    struct PingCall {
        let generation: UInt64
    }
    private(set) var pingCalls: [PingCall] = []
    private var __innodi_pingIsStubbed = false
    private var __innodi_pingReturnValueStorage: Int?
    var pingReturnValue: Int? {
        get {
            __innodi_pingReturnValueStorage
        }
        set {
            __innodi_pingReturnValueStorage = newValue
            __innodi_pingIsStubbed = newValue != nil
        }
    }
    func ping() -> Int {
        pingCalls.append(.init(generation: __innodiMockGeneration))
        guard __innodi_pingIsStubbed else {
            preconditionFailure("pingReturnValue was not set on \(Self.self) before ping was invoked")
        }
        guard let value = pingReturnValue else {
            preconditionFailure("Stub storage for Int was unexpectedly empty")
        }
        return value
    }

    var missingStubSelectors: [String] {
        [
            !__innodi_pingIsStubbed ? "ping" : nil
        ].compactMap {
            $0
        }
    }

    var recordedCallCounts: [String: Int] {
        [
            "ping": pingCalls.count
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
                "ping": pingCalls.count
            ]
        )
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        let snapshot = innoDICallHistorySnapshot
        pingCalls.removeAll(keepingCapacity: false)
        if scope == .all {
            __innodi_pingReturnValueStorage = nil
            __innodi_pingIsStubbed = false
        }
        __innodiMockGeneration &+= 1
        return snapshot
    }
}