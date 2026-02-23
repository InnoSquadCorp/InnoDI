import InnoDI
import SwiftUI

public protocol QuoteServiceProtocol {
    func quote() -> String
}

public struct LiveQuoteService: QuoteServiceProtocol {
    public init() {}
    public func quote() -> String { "Live environment quote" }
}

public struct PreviewQuoteService: QuoteServiceProtocol {
    public init() {}
    public func quote() -> String { "Preview environment quote" }
}

public final class QuoteViewModel: ObservableObject {
    @Published private(set) var quote: String

    public init(service: any QuoteServiceProtocol) {
        self.quote = service.quote()
    }
}

@DIContainer
public struct QuoteContainer {
    @Provide(.input)
    var quoteService: any QuoteServiceProtocol

    @Provide(
        .transient,
        factory: { (quoteService: any QuoteServiceProtocol) in
            QuoteViewModel(service: quoteService)
        },
        concrete: true
    )
    var viewModel: QuoteViewModel
}

public struct QuoteView: View {
    @ObservedObject var viewModel: QuoteViewModel

    public init(viewModel: QuoteViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Text(viewModel.quote)
    }
}

#if os(iOS)
#Preview("Preview Injection") {
    let container = QuoteContainer(quoteService: PreviewQuoteService())
    QuoteView(viewModel: container.viewModel)
}
#endif

@main
struct PreviewInjectionExampleMain {
    static func main() {
        let liveContainer = QuoteContainer(quoteService: LiveQuoteService())
        _ = QuoteView(viewModel: liveContainer.viewModel)
    }
}
