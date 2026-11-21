
protocol RareSpellings {
    func _2fa() -> Bool
    func check(_1: Int)
    func schedule(await: Bool, `inout`: Int, copy: borrowing String)
}

/// Auto-generated mock for `RareSpellings` (RFC 0001 stage 2).
final class RareSpellingsMock: RareSpellings {
    init() {
    }

    private var __innodiMockGeneration: UInt64 = 0

    struct _2faCall {
        let generation: UInt64
    }
    private(set) var _2faCalls: [_2faCall] = []
    private var __innodi__2faIsStubbed = false
    private var __innodi__2faReturnValueStorage: Bool?
    var _2faReturnValue: Bool? {
        get {
            __innodi__2faReturnValueStorage
        }
        set {
            __innodi__2faReturnValueStorage = newValue
            __innodi__2faIsStubbed = newValue != nil
        }
    }
    func _2fa() -> Bool {
        _2faCalls.append(.init(generation: __innodiMockGeneration))
        guard __innodi__2faIsStubbed else {
            preconditionFailure("_2faReturnValue was not set on \(Self.self) before _2fa was invoked")
        }
        guard let value = _2faReturnValue else {
            preconditionFailure("Stub storage for Bool was unexpectedly empty")
        }
        return value
    }

    struct CheckCall {
        let generation: UInt64
        let _1: Int
    }
    private(set) var checkCalls: [CheckCall] = []
    func check(_1: Int) {
        checkCalls.append(.init(generation: __innodiMockGeneration, _1: _1))
    }

    struct ScheduleCall {
        let generation: UInt64
        let await: Bool
        let `inout`: Int
        let copy: String
    }
    private(set) var scheduleCalls: [ScheduleCall] = []
    func schedule(await: Bool, `inout`: Int, copy: borrowing String) {
        scheduleCalls.append(.init(generation: __innodiMockGeneration, await: `await`, `inout`: `inout`, copy: copy copy))
    }

    var missingStubSelectors: [String] {
        [
            !__innodi__2faIsStubbed ? "_2fa" : nil
        ].compactMap {
            $0
        }
    }

    var recordedCallCounts: [String: Int] {
        [
            "_2fa": _2faCalls.count,
            "check": checkCalls.count,
            "schedule": scheduleCalls.count
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
                "_2fa": _2faCalls.count,
                "check": checkCalls.count,
                "schedule": scheduleCalls.count
            ]
        )
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        let snapshot = innoDICallHistorySnapshot
        _2faCalls.removeAll(keepingCapacity: false)
        checkCalls.removeAll(keepingCapacity: false)
        scheduleCalls.removeAll(keepingCapacity: false)
        if scope == .all {
            __innodi__2faReturnValueStorage = nil
            __innodi__2faIsStubbed = false
        }
        __innodiMockGeneration &+= 1
        return snapshot
    }
}
protocol SharedRareSpellings: Sendable {
    func schedule(await: Bool, `inout`: Int, copy: borrowing String)
}

/// Auto-generated mock for `SharedRareSpellings` (RFC 0001 stage 2).
final class SharedRareSpellingsMock: SharedRareSpellings {
    init() {
    }

    private let __innodiMockState = InnoDITesting.DIConcurrentMockState()

    struct ScheduleCall: Sendable {
        let generation: UInt64
        let await: Bool
        let `inout`: Int
        let copy: String
    }
    private let __innodi_scheduleCallsBox = InnoDITesting.DIConcurrentValueBox<[ScheduleCall]>([])
    var scheduleCalls: [ScheduleCall] {
        __innodiMockState.withCriticalRegion { _ in
            __innodi_scheduleCallsBox.snapshot()
        }
    }
    func schedule(await: Bool, `inout`: Int, copy: borrowing String) {
        let __innodiCopyCopy = copy copy
        __innodiMockState.withCriticalRegion { generation in
                    __innodi_scheduleCallsBox.update {
                        $0.append(.init(generation: generation, await: `await`, `inout`: `inout`, copy: __innodiCopyCopy))
                    }
                }
    }

    var recordedCallCounts: [String: Int] {
        __innodiMockState.withCriticalRegion { _ in
            [
                "schedule": __innodi_scheduleCallsBox.snapshot().count
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
                "schedule": __innodi_scheduleCallsBox.snapshot().count
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
                "schedule": __innodi_scheduleCallsBox.snapshot().count
                ]
            )
            __innodi_scheduleCallsBox.replace(with: [])
            if scope == .all {

            }
            return snapshot
        }
    }
}