
protocol AsyncService {
    func fetch(id: String) async throws -> String
    func refresh() async throws
}

/// Auto-generated mock for `AsyncService` (RFC 0001 stage 2).
final class AsyncServiceMock: AsyncService {
    init() {
    }

    private var __innodiMockGeneration: UInt64 = 0

    struct _InnoDIMockNotStubbed: Error, CustomStringConvertible {
        let selector: String
        var description: String {
            "InnoDI mock selector '\(selector)' was not stubbed before invocation."
        }
    }

    struct FetchCall {
        let generation: UInt64
        let id: String
    }
    private(set) var fetchCalls: [FetchCall] = []
    private var __innodi_fetchIsStubbed = false
    private var __innodi_fetchResultStorage: Result<String, Error> = .failure(_InnoDIMockNotStubbed(selector: "fetchResult"))
    var fetchResult: Result<String, Error> {
        get {
            __innodi_fetchResultStorage
        }
        set {
            __innodi_fetchResultStorage = newValue
            __innodi_fetchIsStubbed = true
        }
    }
    func fetch(id: String) async throws -> String {
        fetchCalls.append(.init(generation: __innodiMockGeneration, id: id))
        return try fetchResult.get()
    }

    struct RefreshCall {
        let generation: UInt64
    }
    private(set) var refreshCalls: [RefreshCall] = []
    private var __innodi_refreshIsStubbed = false
    private var __innodi_refreshThrownErrorStorage: Error?
    var refreshThrownError: Error? {
        get {
            __innodi_refreshThrownErrorStorage
        }
        set {
            __innodi_refreshThrownErrorStorage = newValue
            __innodi_refreshIsStubbed = true
        }
    }
    func refresh() async throws {
        refreshCalls.append(.init(generation: __innodiMockGeneration))
        if let error = refreshThrownError {
            throw error
        }
    }

    var missingStubSelectors: [String] {
        [
            !__innodi_fetchIsStubbed ? "fetch" : nil,
            !__innodi_refreshIsStubbed ? "refresh" : nil
        ].compactMap {
            $0
        }
    }

    var recordedCallCounts: [String: Int] {
        [
            "fetch": fetchCalls.count,
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
                "fetch": fetchCalls.count,
                "refresh": refreshCalls.count
            ]
        )
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        let snapshot = innoDICallHistorySnapshot
        fetchCalls.removeAll(keepingCapacity: false)
        refreshCalls.removeAll(keepingCapacity: false)
        if scope == .all {
            __innodi_fetchResultStorage = .failure(_InnoDIMockNotStubbed(selector: "fetchResult"))
            __innodi_fetchIsStubbed = false
            __innodi_refreshThrownErrorStorage = nil
            __innodi_refreshIsStubbed = false
        }
        __innodiMockGeneration &+= 1
        return snapshot
    }
}