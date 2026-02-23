import InnoDI
import SwiftUI

protocol GreetingServiceProtocol {
    func message() -> String
}

struct LiveGreetingService: GreetingServiceProtocol {
    let username: String
    func message() -> String { "Hello, \(username)!" }
}

struct MockGreetingService: GreetingServiceProtocol {
    let text: String
    func message() -> String { text }
}

final class GreetingViewModel: ObservableObject {
    @Published private(set) var text: String

    init(service: any GreetingServiceProtocol) {
        text = service.message()
    }
}

@DIContainer(root: true)
struct AppContainer {
    @Provide(.input)
    var username: String

    @Provide(
        .shared,
        factory: { (username: String) in
            LiveGreetingService(username: username)
        }
    )
    var greetingService: any GreetingServiceProtocol

    @Provide(
        .transient,
        factory: { (greetingService: any GreetingServiceProtocol) in
            GreetingViewModel(service: greetingService)
        },
        concrete: true
    )
    var greetingViewModel: GreetingViewModel
}

struct GreetingView: View {
    @ObservedObject var viewModel: GreetingViewModel

    var body: some View {
        Text(viewModel.text)
    }
}

@main
struct SwiftUIExampleMain {
    static func main() {
        let liveContainer = AppContainer(username: "InnoDI")
        _ = GreetingView(viewModel: liveContainer.greetingViewModel)

        let mockContainer = AppContainer(
            username: "Ignored",
            greetingService: MockGreetingService(text: "Hello from mock")
        )
        _ = GreetingView(viewModel: mockContainer.greetingViewModel)
    }
}
