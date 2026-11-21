
protocol SharedMover: Sendable {
    func move(_ from: borrowing String, _ to: consuming String)
    func send(_ value: sending String)
    func single(_ from: borrowing String, _ to: String)
    func plain(_ value: String)
}

/// Auto-generated mock for `SharedMover` (RFC 0001 stage 2).
final class SharedMoverMock: SharedMover {
    init() {
    }

    private let __innodiMockState = InnoDITesting.DIConcurrentMockState()

    struct MoveCall: Sendable {
        let generation: UInt64
        let from: String
        let to: String
    }
    private let __innodi_moveCallsBox = InnoDITesting.DIConcurrentValueBox<[MoveCall]>([])
    var moveCalls: [MoveCall] {
        __innodiMockState.withCriticalRegion { _ in
            __innodi_moveCallsBox.snapshot()
        }
    }
    func move(_ from: borrowing String, _ to: consuming String) {
        let __innodiFromCopy = copy from
        let __innodiToCopy = copy to
        __innodiMockState.withCriticalRegion { generation in
                    __innodi_moveCallsBox.update {
                        $0.append(.init(generation: generation, from: __innodiFromCopy, to: __innodiToCopy))
                    }
                }
    }

    struct SendCall: Sendable {
        let generation: UInt64
        let value: String
    }
    private let __innodi_sendCallsBox = InnoDITesting.DIConcurrentValueBox<[SendCall]>([])
    var sendCalls: [SendCall] {
        __innodiMockState.withCriticalRegion { _ in
            __innodi_sendCallsBox.snapshot()
        }
    }
    func send(_ value: sending String) {
        let __innodiValueCopy = copy value
        __innodiMockState.withCriticalRegion { generation in
                    __innodi_sendCallsBox.update {
                        $0.append(.init(generation: generation, value: __innodiValueCopy))
                    }
                }
    }

    struct SingleCall: Sendable {
        let generation: UInt64
        let from: String
        let to: String
    }
    private let __innodi_singleCallsBox = InnoDITesting.DIConcurrentValueBox<[SingleCall]>([])
    var singleCalls: [SingleCall] {
        __innodiMockState.withCriticalRegion { _ in
            __innodi_singleCallsBox.snapshot()
        }
    }
    func single(_ from: borrowing String, _ to: String) {
        let __innodiFromCopy = copy from
        __innodiMockState.withCriticalRegion { generation in
                    __innodi_singleCallsBox.update {
                        $0.append(.init(generation: generation, from: __innodiFromCopy, to: to))
                    }
                }
    }

    struct PlainCall: Sendable {
        let generation: UInt64
        let value: String
    }
    private let __innodi_plainCallsBox = InnoDITesting.DIConcurrentValueBox<[PlainCall]>([])
    var plainCalls: [PlainCall] {
        __innodiMockState.withCriticalRegion { _ in
            __innodi_plainCallsBox.snapshot()
        }
    }
    func plain(_ value: String) {
        __innodiMockState.withCriticalRegion { generation in
            __innodi_plainCallsBox.update {
                $0.append(.init(generation: generation, value: value))
            }
        }
    }

    var recordedCallCounts: [String: Int] {
        __innodiMockState.withCriticalRegion { _ in
            [
                "move": __innodi_moveCallsBox.snapshot().count,
                "send": __innodi_sendCallsBox.snapshot().count,
                "single": __innodi_singleCallsBox.snapshot().count,
                "plain": __innodi_plainCallsBox.snapshot().count
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
                "move": __innodi_moveCallsBox.snapshot().count,
                "send": __innodi_sendCallsBox.snapshot().count,
                "single": __innodi_singleCallsBox.snapshot().count,
                "plain": __innodi_plainCallsBox.snapshot().count
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
                "move": __innodi_moveCallsBox.snapshot().count,
                "send": __innodi_sendCallsBox.snapshot().count,
                "single": __innodi_singleCallsBox.snapshot().count,
                "plain": __innodi_plainCallsBox.snapshot().count
                ]
            )
            __innodi_moveCallsBox.replace(with: [])
            __innodi_sendCallsBox.replace(with: [])
            __innodi_singleCallsBox.replace(with: [])
            __innodi_plainCallsBox.replace(with: [])
            if scope == .all {

            }
            return snapshot
        }
    }
}
protocol Mover {
    func move(_ from: borrowing String, _ to: consuming String)
    func send(_ value: sending String)
}

/// Auto-generated mock for `Mover` (RFC 0001 stage 2).
final class MoverMock: Mover {
    init() {
    }

    private var __innodiMockGeneration: UInt64 = 0

    struct MoveCall {
        let generation: UInt64
        let from: String
        let to: String
    }
    private(set) var moveCalls: [MoveCall] = []
    func move(_ from: borrowing String, _ to: consuming String) {
        moveCalls.append(.init(generation: __innodiMockGeneration, from: copy from, to: copy to))
    }

    struct SendCall {
        let generation: UInt64
        let value: String
    }
    private(set) var sendCalls: [SendCall] = []
    func send(_ value: sending String) {
        sendCalls.append(.init(generation: __innodiMockGeneration, value: value))
    }

    var recordedCallCounts: [String: Int] {
        [
            "move": moveCalls.count,
            "send": sendCalls.count
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
                "move": moveCalls.count,
                "send": sendCalls.count
            ]
        )
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        let snapshot = innoDICallHistorySnapshot
        moveCalls.removeAll(keepingCapacity: false)
        sendCalls.removeAll(keepingCapacity: false)
        if scope == .all {

        }
        __innodiMockGeneration &+= 1
        return snapshot
    }
}