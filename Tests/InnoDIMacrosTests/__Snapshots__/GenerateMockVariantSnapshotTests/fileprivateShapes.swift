
fileprivate protocol Clock: AnyObject {
    var now: Double { get }
}

/// Auto-generated mock for `Clock` (RFC 0001 stage 2).
fileprivate final class ClockMock: Clock {
    init() {
    }

    private var __innodiMockGeneration: UInt64 = 0

    private var __innodi_now_h215ad519258e9d97StubValue: Double?
    private var __innodi_now_h215ad519258e9d97IsStubbed = false
    var now: Double {
        get {
            guard __innodi_now_h215ad519258e9d97IsStubbed else {
                preconditionFailure("now was not set on \(Self.self) before it was read")
            }
                guard let value = __innodi_now_h215ad519258e9d97StubValue else {
        preconditionFailure("Stub storage for Double was unexpectedly empty")
    }
    return value
        }
        set {
            __innodi_now_h215ad519258e9d97StubValue = newValue
            __innodi_now_h215ad519258e9d97IsStubbed = true
        }
    }

    var missingStubSelectors: [String] {
        [
            !__innodi_now_h215ad519258e9d97IsStubbed ? "now" : nil
        ].compactMap {
            $0
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
        __innodiMockGeneration
    }

    var innoDICallHistorySnapshot: InnoDICallHistorySnapshot {
        .init(
            generation: __innodiMockGeneration,
            recordedCallCounts: [
                :
            ]
        )
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        let snapshot = innoDICallHistorySnapshot

        if scope == .all {
            __innodi_now_h215ad519258e9d97StubValue = nil
            __innodi_now_h215ad519258e9d97IsStubbed = false
        }
        __innodiMockGeneration &+= 1
        return snapshot
    }
}