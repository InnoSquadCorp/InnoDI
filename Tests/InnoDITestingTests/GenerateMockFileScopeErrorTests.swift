import InnoDITesting
import Testing

// A type named `Error` at file scope hides `Swift.Error` in this whole file,
// including the peer mocks expanded here (G9). `fileprivate` keeps the
// shadow out of the target's other files.
fileprivate struct Error {}

@GenerateMock
fileprivate protocol FileScopeErrorAPI {
    func send() throws -> Int
    func ping() throws
}

@GenerateMock
fileprivate protocol SharedFileScopeErrorAPI: Sendable {
    func send() throws -> Int
    func ping() throws
}

@Suite("GenerateMock next to a file-scope Error type")
struct GenerateMockFileScopeErrorTests {
    private struct Failure: Swift.Error {}

    @Test("Throwing stubs keep Swift's Error")
    func throwingStubsUseSwiftError() throws {
        _ = Error()
        let mock = FileScopeErrorAPIMock()
        mock.sendResult = .success(2)
        #expect(try mock.send() == 2)
        mock.pingThrownError = Failure()
        #expect(throws: Failure.self) { try mock.ping() }

        let shared = SharedFileScopeErrorAPIMock()
        shared.sendResult = .failure(Failure())
        #expect(throws: Failure.self) { try shared.send() }
    }
}
