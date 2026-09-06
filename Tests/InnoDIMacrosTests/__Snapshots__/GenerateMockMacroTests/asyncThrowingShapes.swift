
protocol AsyncService {
    func fetch(id: String) async throws -> String
    func refresh() async throws
}

/// Auto-generated mock for `AsyncService` (RFC 0001 stage 2).
final class AsyncServiceMock: AsyncService {
    init() {
    }

    struct _InnoDIMockNotStubbed: Error, CustomStringConvertible {
        let selector: String
        var description: String {
            "InnoDI mock selector '\(selector)' was not stubbed before invocation."
        }
    }

    struct FetchCall {
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
        fetchCalls.append(.init(id: id))
        return try fetchResult.get()
    }

    struct RefreshCall {
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
        refreshCalls.append(.init())
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
}