
protocol Catalog {
    var title: String { get set }
    var count: Int { get }
    func item(at index: Int) -> String
    func reload()
    mutating func reset(to value: Int)
}

/// Auto-generated mock for `Catalog` (RFC 0001 stage 2).
final class CatalogMock: Catalog {
    init() {
    }

    private var __innodiMockGeneration: UInt64 = 0

    private var __innodi_title_hda31296c0c1b6029StubValue: String?
    private var __innodi_title_hda31296c0c1b6029IsStubbed = false
    var title: String {
        get {
            guard __innodi_title_hda31296c0c1b6029IsStubbed else {
                preconditionFailure("title was not set on \(Self.self) before it was read")
            }
            guard let value = __innodi_title_hda31296c0c1b6029StubValue else {
                preconditionFailure("Stub storage for String was unexpectedly empty")
            }
            return value
        }
        set {
            __innodi_title_hda31296c0c1b6029StubValue = newValue
            __innodi_title_hda31296c0c1b6029IsStubbed = true
        }
    }

    private var __innodi_count_hb1e5e28e4479a274StubValue: Int?
    private var __innodi_count_hb1e5e28e4479a274IsStubbed = false
    var count: Int {
        get {
            guard __innodi_count_hb1e5e28e4479a274IsStubbed else {
                preconditionFailure("count was not set on \(Self.self) before it was read")
            }
            guard let value = __innodi_count_hb1e5e28e4479a274StubValue else {
                preconditionFailure("Stub storage for Int was unexpectedly empty")
            }
            return value
        }
        set {
            __innodi_count_hb1e5e28e4479a274StubValue = newValue
            __innodi_count_hb1e5e28e4479a274IsStubbed = true
        }
    }

    struct ItemCall {
        let generation: UInt64
        let index: Int
    }
    private(set) var itemCalls: [ItemCall] = []
    private var __innodi_itemIsStubbed = false
    private var __innodi_itemReturnValueStorage: String?
    var itemReturnValue: String? {
        get {
            __innodi_itemReturnValueStorage
        }
        set {
            __innodi_itemReturnValueStorage = newValue
            __innodi_itemIsStubbed = true
        }
    }
    func item(at index: Int) -> String {
        itemCalls.append(.init(generation: __innodiMockGeneration, index: index))
        guard __innodi_itemIsStubbed else {
            preconditionFailure("itemReturnValue was not set on \(Self.self) before item was invoked")
        }
        guard let value = itemReturnValue else {
            preconditionFailure("Stub storage for String was unexpectedly empty")
        }
        return value
    }

    struct ReloadCall {
        let generation: UInt64
    }
    private(set) var reloadCalls: [ReloadCall] = []
    func reload() {
        reloadCalls.append(.init(generation: __innodiMockGeneration))
    }

    struct ResetCall {
        let generation: UInt64
        let value: Int
    }
    private(set) var resetCalls: [ResetCall] = []
    func reset(to value: Int) {
        resetCalls.append(.init(generation: __innodiMockGeneration, value: value))
    }

    var missingStubSelectors: [String] {
        [
            !__innodi_title_hda31296c0c1b6029IsStubbed ? "title" : nil,
            !__innodi_count_hb1e5e28e4479a274IsStubbed ? "count" : nil,
            !__innodi_itemIsStubbed ? "item" : nil
        ].compactMap {
            $0
        }
    }

    var recordedCallCounts: [String: Int] {
        [
            "item": itemCalls.count,
            "reload": reloadCalls.count,
            "reset": resetCalls.count
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
                "item": itemCalls.count,
                "reload": reloadCalls.count,
                "reset": resetCalls.count
            ]
        )
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        let snapshot = innoDICallHistorySnapshot
        itemCalls.removeAll(keepingCapacity: false)
        reloadCalls.removeAll(keepingCapacity: false)
        resetCalls.removeAll(keepingCapacity: false)
        if scope == .all {
            __innodi_title_hda31296c0c1b6029StubValue = nil
            __innodi_title_hda31296c0c1b6029IsStubbed = false
            __innodi_count_hb1e5e28e4479a274StubValue = nil
            __innodi_count_hb1e5e28e4479a274IsStubbed = false
            __innodi_itemReturnValueStorage = nil
            __innodi_itemIsStubbed = false
        }
        __innodiMockGeneration &+= 1
        return snapshot
    }
}