
protocol Scheduler {
    func schedule(_ work: @escaping @Sendable () -> Void) -> (() -> Void)?
    func cancel(_: Int, reason: String) -> ()
    func lookup(`default`: String) -> String?
}

/// Auto-generated mock for `Scheduler` (RFC 0001 stage 2).
final class SchedulerMock: Scheduler {
    init() {
    }

    private var __innodiMockGeneration: UInt64 = 0

    struct ScheduleCall {
        let generation: UInt64
        let work: @Sendable () -> Void
    }
    private(set) var scheduleCalls: [ScheduleCall] = []
    private var __innodi_scheduleIsStubbed = false
    private var __innodi_scheduleReturnValueStorage: ((() -> Void)?)?
    var scheduleReturnValue: ((() -> Void)?)? {
        get {
            __innodi_scheduleReturnValueStorage
        }
        set {
            __innodi_scheduleReturnValueStorage = newValue
            __innodi_scheduleIsStubbed = true
        }
    }
    func schedule(_ work: @escaping @Sendable () -> Void) -> (() -> Void)? {
        scheduleCalls.append(.init(generation: __innodiMockGeneration, work: work))
        guard __innodi_scheduleIsStubbed else {
            preconditionFailure("scheduleReturnValue was not set on \(Self.self) before schedule was invoked")
        }
        return scheduleReturnValue ?? nil
    }

    struct CancelCall {
        let generation: UInt64
        let value1: Int
        let reason: String
    }
    private(set) var cancelCalls: [CancelCall] = []
    func cancel(_ value1: Int, reason: String) {
        cancelCalls.append(.init(generation: __innodiMockGeneration, value1: value1, reason: reason))
    }

    struct LookupCall {
        let generation: UInt64
        let `default`: String
    }
    private(set) var lookupCalls: [LookupCall] = []
    private var __innodi_lookupIsStubbed = false
    private var __innodi_lookupReturnValueStorage: (String?)?
    var lookupReturnValue: (String?)? {
        get {
            __innodi_lookupReturnValueStorage
        }
        set {
            __innodi_lookupReturnValueStorage = newValue
            __innodi_lookupIsStubbed = true
        }
    }
    func lookup(`default`: String) -> String? {
        lookupCalls.append(.init(generation: __innodiMockGeneration, default: `default`))
        guard __innodi_lookupIsStubbed else {
            preconditionFailure("lookupReturnValue was not set on \(Self.self) before lookup was invoked")
        }
        return lookupReturnValue ?? nil
    }

    var missingStubSelectors: [String] {
        [
            !__innodi_scheduleIsStubbed ? "schedule" : nil,
            !__innodi_lookupIsStubbed ? "lookup" : nil
        ].compactMap {
            $0
        }
    }

    var recordedCallCounts: [String: Int] {
        [
            "schedule": scheduleCalls.count,
            "cancel": cancelCalls.count,
            "lookup": lookupCalls.count
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
                "schedule": scheduleCalls.count,
                "cancel": cancelCalls.count,
                "lookup": lookupCalls.count
            ]
        )
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        let snapshot = innoDICallHistorySnapshot
        scheduleCalls.removeAll(keepingCapacity: false)
        cancelCalls.removeAll(keepingCapacity: false)
        lookupCalls.removeAll(keepingCapacity: false)
        if scope == .all {
            __innodi_scheduleReturnValueStorage = nil
            __innodi_scheduleIsStubbed = false
            __innodi_lookupReturnValueStorage = nil
            __innodi_lookupIsStubbed = false
        }
        __innodiMockGeneration &+= 1
        return snapshot
    }
}