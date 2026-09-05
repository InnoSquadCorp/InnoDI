
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
    var fetchResult: Result<String, Error> = .failure(_InnoDIMockNotStubbed(selector: "fetchResult"))
    func fetch(id: String) async throws -> String {
        fetchCalls.append(.init(id: id))
        return try fetchResult.get()
    }

    struct RefreshCall {
    }
    private(set) var refreshCalls: [RefreshCall] = []
    var refreshThrownError: Error?
    func refresh() async throws {
        refreshCalls.append(.init())
        if let error = refreshThrownError {
            throw error
        }
    }

    var recordedCallCounts: [String: Int] {
        [
            "fetch": fetchCalls.count,
            "refresh": refreshCalls.count
        ]
    }
}
