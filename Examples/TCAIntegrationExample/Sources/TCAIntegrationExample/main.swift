import ComposableArchitecture
import InnoDI

protocol CounterClientProtocol {
    func load() -> Int
}

struct LiveCounterClient: CounterClientProtocol {
    let initial: Int
    func load() -> Int { initial }
}

struct MockCounterClient: CounterClientProtocol {
    let value: Int
    func load() -> Int { value }
}

@DIContainer(root: true)
struct CounterContainer {
    @Provide(.input)
    var initialCount: Int

    @Provide(
        .shared,
        factory: { (initialCount: Int) in
            LiveCounterClient(initial: initialCount)
        },
        concrete: true
    )
    var liveCounterClient: LiveCounterClient

    @Provide(
        .shared,
        factory: { (liveCounterClient: LiveCounterClient) in
            liveCounterClient
        }
    )
    var counterClient: any CounterClientProtocol
}

@Reducer
struct CounterFeature {
    @ObservableState
    struct State: Equatable {
        var count: Int = 0
    }

    enum Action: Equatable {
        case incrementTapped
        case loadTapped
        case loaded(Int)
    }

    let counterClient: any CounterClientProtocol

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .incrementTapped:
                state.count += 1
                return .none

            case .loadTapped:
                return .send(.loaded(counterClient.load()))

            case let .loaded(value):
                state.count = value
                return .none
            }
        }
    }
}

@main
struct TCAIntegrationExampleMain {
    static func main() {
        let liveContainer = CounterContainer(initialCount: 10)
        let _ = Store(initialState: CounterFeature.State()) {
            CounterFeature(counterClient: liveContainer.counterClient)
        }

        let testContainer = CounterContainer(
            initialCount: 0,
            counterClient: MockCounterClient(value: 42)
        )
        let _ = Store(initialState: CounterFeature.State()) {
            CounterFeature(counterClient: testContainer.counterClient)
        }
    }
}
