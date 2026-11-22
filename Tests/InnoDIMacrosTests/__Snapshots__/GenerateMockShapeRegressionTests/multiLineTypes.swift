
protocol Pager {
    func page() -> (
        items: [Int], // first page
        next: Int?
    )
    var cursor: (
        offset: Int,
        limit: Int
    ) { get set }
    func decode<T>(_ type: T.Type) -> (
        value: T,
        count: Int
    )
    func optionalPage() -> (
        items: [Int],
        next: Int?
    )?
    func single() -> (items: [Int], next: Int?)
}

/// Auto-generated mock for `Pager` (RFC 0001 stage 2).
final class PagerMock: Pager {
    init() {
    }

    private var __innodiMockGeneration: UInt64 = 0

    struct PageCall {
        let generation: UInt64
    }
    private(set) var pageCalls: [PageCall] = []
    private var __innodi_pageIsStubbed = false
    private var __innodi_pageReturnValueStorage: (
        items: [Int], // first page
        next: Int?
    )?
    var pageReturnValue: (
        items: [Int], // first page
        next: Int?
    )? {
        get {
            __innodi_pageReturnValueStorage
        }
        set {
            __innodi_pageReturnValueStorage = newValue
            __innodi_pageIsStubbed = newValue != nil
        }
    }
    func page() -> (
        items: [Int], // first page
        next: Int?
    ) {
        pageCalls.append(.init(generation: __innodiMockGeneration))
        guard __innodi_pageIsStubbed else {
            preconditionFailure("pageReturnValue was not set on \(Self.self) before page was invoked")
        }
        guard let value = pageReturnValue else {
            preconditionFailure("Stub storage for (items: [Int], next: Int?) was unexpectedly empty")
        }
        return value
    }

    private var __innodi_cursor_hf927453fbe6252efStubValue: (
        offset: Int,
        limit: Int
    )?
    private var __innodi_cursor_hf927453fbe6252efIsStubbed = false
    var cursor: (
        offset: Int,
        limit: Int
    ) {
        get {
            guard __innodi_cursor_hf927453fbe6252efIsStubbed else {
                preconditionFailure("cursor was not set on \(Self.self) before it was read")
            }
            guard let value = __innodi_cursor_hf927453fbe6252efStubValue else {
                preconditionFailure("Stub storage for (offset: Int, limit: Int) was unexpectedly empty")
            }
            return value
        }
        set {
            __innodi_cursor_hf927453fbe6252efStubValue = newValue
            __innodi_cursor_hf927453fbe6252efIsStubbed = true
        }
    }

    struct DecodeUnlabeledTTypeCall {
        let generation: UInt64
        let type: Any
    }
    private(set) var decodeUnlabeledTTypeCalls: [DecodeUnlabeledTTypeCall] = []
    private var __innodi_decodeUnlabeledTTypeHandlerStorage: (([Any]) -> Any)?
    private var __innodi_decodeUnlabeledTTypeIsStubbed = false
    var decodeUnlabeledTTypeHandler: (([Any]) -> Any)? {
        get {
            __innodi_decodeUnlabeledTTypeHandlerStorage
        }
        set {
            __innodi_decodeUnlabeledTTypeHandlerStorage = newValue
            __innodi_decodeUnlabeledTTypeIsStubbed = newValue != nil
        }
    }
    func decode<T>(_ type: T.Type) -> (
        value: T,
        count: Int
    ) {
        decodeUnlabeledTTypeCalls.append(.init(generation: __innodiMockGeneration, type: type))
        guard let handler = decodeUnlabeledTTypeHandler else {
            preconditionFailure("decodeUnlabeledTTypeHandler was not set on \(Self.self) before decode was invoked")
        }
        let rawValue = handler([type])
        guard let value = rawValue as? (
        value: T,
        count: Int
    ) else {
            preconditionFailure("decodeUnlabeledTTypeHandler returned a value that cannot be cast to (value: T, count: Int)")
        }
        return value
    }

    struct OptionalPageCall {
        let generation: UInt64
    }
    private(set) var optionalPageCalls: [OptionalPageCall] = []
    private var __innodi_optionalPageIsStubbed = false
    private var __innodi_optionalPageReturnValueStorage: ((
        items: [Int],
        next: Int?
    )?)?
    var optionalPageReturnValue: ((
        items: [Int],
        next: Int?
    )?)? {
        get {
            __innodi_optionalPageReturnValueStorage
        }
        set {
            __innodi_optionalPageReturnValueStorage = newValue
            __innodi_optionalPageIsStubbed = true
        }
    }
    func optionalPage() -> (
        items: [Int],
        next: Int?
    )? {
        optionalPageCalls.append(.init(generation: __innodiMockGeneration))
        guard __innodi_optionalPageIsStubbed else {
            preconditionFailure("optionalPageReturnValue was not set on \(Self.self) before optionalPage was invoked")
        }
        return optionalPageReturnValue ?? nil
    }

    struct SingleCall {
        let generation: UInt64
    }
    private(set) var singleCalls: [SingleCall] = []
    private var __innodi_singleIsStubbed = false
    private var __innodi_singleReturnValueStorage: (items: [Int], next: Int?)?
    var singleReturnValue: (items: [Int], next: Int?)? {
        get {
            __innodi_singleReturnValueStorage
        }
        set {
            __innodi_singleReturnValueStorage = newValue
            __innodi_singleIsStubbed = newValue != nil
        }
    }
    func single() -> (items: [Int], next: Int?) {
        singleCalls.append(.init(generation: __innodiMockGeneration))
        guard __innodi_singleIsStubbed else {
            preconditionFailure("singleReturnValue was not set on \(Self.self) before single was invoked")
        }
        guard let value = singleReturnValue else {
            preconditionFailure("Stub storage for (items: [Int], next: Int?) was unexpectedly empty")
        }
        return value
    }

    var missingStubSelectors: [String] {
        [
            !__innodi_pageIsStubbed ? "page" : nil,
            !__innodi_cursor_hf927453fbe6252efIsStubbed ? "cursor" : nil,
            !__innodi_decodeUnlabeledTTypeIsStubbed ? "decodeUnlabeledTType" : nil,
            !__innodi_optionalPageIsStubbed ? "optionalPage" : nil,
            !__innodi_singleIsStubbed ? "single" : nil
        ].compactMap {
            $0
        }
    }

    var recordedCallCounts: [String: Int] {
        [
            "page": pageCalls.count,
            "decodeUnlabeledTType": decodeUnlabeledTTypeCalls.count,
            "optionalPage": optionalPageCalls.count,
            "single": singleCalls.count
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
                "page": pageCalls.count,
                "decodeUnlabeledTType": decodeUnlabeledTTypeCalls.count,
                "optionalPage": optionalPageCalls.count,
                "single": singleCalls.count
            ]
        )
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        let snapshot = innoDICallHistorySnapshot
        pageCalls.removeAll(keepingCapacity: false)
        decodeUnlabeledTTypeCalls.removeAll(keepingCapacity: false)
        optionalPageCalls.removeAll(keepingCapacity: false)
        singleCalls.removeAll(keepingCapacity: false)
        if scope == .all {
            __innodi_pageReturnValueStorage = nil
            __innodi_pageIsStubbed = false
            __innodi_cursor_hf927453fbe6252efStubValue = nil
            __innodi_cursor_hf927453fbe6252efIsStubbed = false
            __innodi_decodeUnlabeledTTypeHandlerStorage = nil
            __innodi_decodeUnlabeledTTypeIsStubbed = false
            __innodi_optionalPageReturnValueStorage = nil
            __innodi_optionalPageIsStubbed = false
            __innodi_singleReturnValueStorage = nil
            __innodi_singleIsStubbed = false
        }
        __innodiMockGeneration &+= 1
        return snapshot
    }
}