// Patterns adapted from InnoDI 7.0.0; see ../../../../THIRD_PARTY_NOTICES.md.
import InnoDI

struct APIClient: Equatable, Sendable {
    let baseURL: String
}

@MainActor
final class ConstructionCount {
    var value = 0
    func makeLabel() -> String {
        value += 1
        return "live"
    }
}

@DIContainerRole(role: ContainerRole.local, mainActor: true)
struct AppServices {
    @Input var baseURL: String
    @Input var count: ConstructionCount

    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
    var client: APIClient

    @Provide(.shared, initialization: .onDemand,
             factory: { (count: ConstructionCount) -> String? in count.makeLabel() })
    var label: String?
}

enum ExampleFailure: Error {
    case unavailable
    case operation
}

actor SessionLoader {
    private(set) var attempts = 0
    private let failFirst: Bool
    private let gateFirst: Bool
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    init(failFirst: Bool = false, gateFirst: Bool = false) {
        self.failFirst = failFirst
        self.gateFirst = gateFirst
    }

    func open() async throws -> Int {
        attempts += 1
        if attempts == 1 && gateFirst {
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
                let waiters = startWaiters
                startWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
            }
        }
        if attempts == 1 && failFirst { throw ExampleFailure.unavailable }
        return 42
    }

    func waitUntilStarted() async {
        if attempts > 0 { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@DIContainerRole(role: ContainerRole.local, mainActor: true, generateOwned: true)
struct SessionServices {
    @Input var loader: SessionLoader

    @Provide(.shared, initialization: .onDemand,
             asyncFactory: { (loader: SessionLoader) async throws in try await loader.open() })
    var session: Int
}
