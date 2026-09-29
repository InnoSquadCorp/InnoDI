@MainActor
protocol ScreenModel {
    var isLoading: Bool { get }
    func present(_ message: String)
    func refresh() async throws -> [String]
}

/// Auto-generated mock for `ScreenModel` (RFC 0001 stage 2).
@MainActor
final class ScreenModelMock: ScreenModel {
    init() {
    }

    private var __innodiMockGeneration: UInt64 = 0

    struct _InnoDIMockNotStubbed: Error, CustomStringConvertible {
        let selector: String
        var description: String {
            "InnoDI mock selector '\(selector)' was not stubbed before invocation."
        }
    }

    private var __innodi_isLoading_hc6486b6d6941d887StubValue: Bool?
    private var __innodi_isLoading_hc6486b6d6941d887IsStubbed = false
    var isLoading: Bool {
        get {
            guard __innodi_isLoading_hc6486b6d6941d887IsStubbed else {
                preconditionFailure("isLoading was not set on \(Self.self) before it was read")
            }
                guard let value = __innodi_isLoading_hc6486b6d6941d887StubValue else {
        preconditionFailure("Stub storage for Bool was unexpectedly empty")
    }
    return value
        }
        set {
            __innodi_isLoading_hc6486b6d6941d887StubValue = newValue
            __innodi_isLoading_hc6486b6d6941d887IsStubbed = true
        }
    }

    struct PresentCall {
        let generation: UInt64
        let message: String
    }
    private(set) var presentCalls: [PresentCall] = []
    func present(_ message: String) {
        presentCalls.append(.init(generation: __innodiMockGeneration, message: message))
    }

    struct RefreshCall {
        let generation: UInt64
    }
    private(set) var refreshCalls: [RefreshCall] = []
    private var __innodi_refreshIsStubbed = false
    private var __innodi_refreshResultStorage: Result<[String], Error> = .failure(_InnoDIMockNotStubbed(selector: "refreshResult"))
    var refreshResult: Result<[String], Error> {
        get {
            __innodi_refreshResultStorage
        }
        set {
            __innodi_refreshResultStorage = newValue
            __innodi_refreshIsStubbed = true
        }
    }
    func refresh() async throws -> [String] {
        refreshCalls.append(.init(generation: __innodiMockGeneration))
        return try refreshResult.get()
    }

    var missingStubSelectors: [String] {
        [
            !__innodi_isLoading_hc6486b6d6941d887IsStubbed ? "isLoading" : nil,
            !__innodi_refreshIsStubbed ? "refresh" : nil
        ].compactMap {
            $0
        }
    }

    var recordedCallCounts: [String: Int] {
        [
            "present": presentCalls.count,
            "refresh": refreshCalls.count
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
                "present": presentCalls.count,
                "refresh": refreshCalls.count
            ]
        )
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        let snapshot = innoDICallHistorySnapshot
        presentCalls.removeAll(keepingCapacity: false)
        refreshCalls.removeAll(keepingCapacity: false)
        if scope == .all {
            __innodi_isLoading_hc6486b6d6941d887StubValue = nil
            __innodi_isLoading_hc6486b6d6941d887IsStubbed = false
            __innodi_refreshResultStorage = .failure(_InnoDIMockNotStubbed(selector: "refreshResult"))
            __innodi_refreshIsStubbed = false
        }
        __innodiMockGeneration &+= 1
        return snapshot
    }
}