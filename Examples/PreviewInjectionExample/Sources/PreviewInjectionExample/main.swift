import InnoDI
import Observation
import SwiftUI

enum QuotePreviewError: Error, LocalizedError, Sendable {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Preview services failed. Swap the root override or retry the load."
        }
    }
}

public protocol QuoteServiceProtocol: Sendable {
    func quote() async throws -> String
}

public protocol QuoteMetaServiceProtocol: Sendable {
    func byline() async throws -> String
}

public struct DelayedQuoteService: QuoteServiceProtocol {
    let text: String
    let delayMilliseconds: Int

    public init(text: String, delayMilliseconds: Int) {
        self.text = text
        self.delayMilliseconds = delayMilliseconds
    }

    public func quote() async throws -> String {
        try await Task.sleep(for: .milliseconds(delayMilliseconds))
        return text
    }
}

public struct DelayedQuoteMetaService: QuoteMetaServiceProtocol {
    let text: String
    let delayMilliseconds: Int

    public init(text: String, delayMilliseconds: Int) {
        self.text = text
        self.delayMilliseconds = delayMilliseconds
    }

    public func byline() async throws -> String {
        try await Task.sleep(for: .milliseconds(delayMilliseconds))
        return text
    }
}

public struct FailingQuoteService: QuoteServiceProtocol {
    public init() {}

    public func quote() async throws -> String {
        try await Task.sleep(for: .milliseconds(80))
        throw QuotePreviewError.unavailable
    }
}

public struct FailingQuoteMetaService: QuoteMetaServiceProtocol {
    public init() {}

    public func byline() async throws -> String {
        throw QuotePreviewError.unavailable
    }
}

private struct QuoteServiceKey: EnvironmentKey {
    static let defaultValue: any QuoteServiceProtocol = DelayedQuoteService(
        text: "Missing quote service",
        delayMilliseconds: 0
    )
}

private struct QuoteMetaServiceKey: EnvironmentKey {
    static let defaultValue: any QuoteMetaServiceProtocol = DelayedQuoteMetaService(
        text: "Inject quote meta service at the root boundary",
        delayMilliseconds: 0
    )
}

extension EnvironmentValues {
    var quoteService: any QuoteServiceProtocol {
        get { self[QuoteServiceKey.self] }
        set { self[QuoteServiceKey.self] = newValue }
    }

    var quoteMetaService: any QuoteMetaServiceProtocol {
        get { self[QuoteMetaServiceKey.self] }
        set { self[QuoteMetaServiceKey.self] = newValue }
    }
}

public enum QuoteFeaturePhase: Sendable {
    case idle
    case loading
    case loaded(quote: String, byline: String)
    case failed(String)
}

@MainActor
@Observable
public final class QuoteFeatureModel {
    public var phase: QuoteFeaturePhase = .idle
    private var loadTask: Task<Void, Never>?

    public init() {}

    public func load(
        quoteService: any QuoteServiceProtocol,
        quoteMetaService: any QuoteMetaServiceProtocol
    ) {
        cancel()
        phase = .loading

        loadTask = Task { [weak self] in
            do {
                async let quote = quoteService.quote()
                async let byline = quoteMetaService.byline()
                let resolvedQuote = try await quote
                let resolvedByline = try await byline

                guard !Task.isCancelled, let self else { return }
                self.phase = .loaded(quote: resolvedQuote, byline: resolvedByline)
            } catch {
                guard !Task.isCancelled, let self else { return }
                let message = (error as? LocalizedError)?.errorDescription ?? "Unknown preview error."
                self.phase = .failed(message)
            }
        }
    }

    public func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }
}

@DIContainer
public struct QuoteContainer {
    @Provide(.input)
    var quoteService: any QuoteServiceProtocol

    @Provide(.input)
    var quoteMetaService: any QuoteMetaServiceProtocol
}

public struct QuoteLoadingSkeletonView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 14)
                .fill(.quaternary)
                .frame(height: 28)
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.7))
                .frame(height: 18)
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.55))
                .frame(height: 18)
        }
        .redacted(reason: .placeholder)
    }
}

public struct QuoteCardView: View {
    let phase: QuoteFeaturePhase
    let retry: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch phase {
            case .idle, .loading:
                QuoteLoadingSkeletonView()
            case let .loaded(quote, byline):
                Text(quote)
                    .font(.title3.weight(.semibold))
                Text(byline)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case let .failed(message):
                Text("Preview override failed")
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Retry", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
    }
}

public struct QuoteFeatureRootView: View {
    @Environment(\.quoteService) private var quoteService
    @Environment(\.quoteMetaService) private var quoteMetaService
    @State private var model = QuoteFeatureModel()

    public init() {}

    public var body: some View {
        QuoteCardView(phase: model.phase) {
            model.load(quoteService: quoteService, quoteMetaService: quoteMetaService)
        }
        .padding(24)
        .task {
            model.load(quoteService: quoteService, quoteMetaService: quoteMetaService)
        }
        .onDisappear {
            model.cancel()
        }
    }
}

public struct QuoteAppRootView: View {
    let title: String
    let container: QuoteContainer

    public init(title: String, container: QuoteContainer) {
        self.title = title
        self.container = container
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.top, 24)
            QuoteFeatureRootView()
        }
        .environment(\.quoteService, container.quoteService)
        .environment(\.quoteMetaService, container.quoteMetaService)
    }
}

public struct QuotePreviewMatrixView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ForEach(QuotePreviewScenario.allCases, id: \.title) { scenario in
                    QuoteAppRootView(
                        title: scenario.title,
                        container: scenario.container
                    )
                }
            }
            .padding(.vertical, 24)
        }
    }
}

public struct QuotePreviewScenario: CaseIterable {
    public let title: String
    public let container: QuoteContainer

    public static var allCases: [QuotePreviewScenario] {
        [
            QuotePreviewScenario(
                title: "Live",
                container: QuoteContainer(
                    quoteService: DelayedQuoteService(text: "Live environment quote", delayMilliseconds: 120),
                    quoteMetaService: DelayedQuoteMetaService(text: "Delivered by the live feature root", delayMilliseconds: 60)
                )
            ),
            QuotePreviewScenario(
                title: "Preview",
                container: QuoteContainer(
                    quoteService: DelayedQuoteService(text: "Preview environment quote", delayMilliseconds: 0),
                    quoteMetaService: DelayedQuoteMetaService(text: "Preview override injected at the root boundary", delayMilliseconds: 0)
                )
            ),
            QuotePreviewScenario(
                title: "Failure",
                container: QuoteContainer(
                    quoteService: FailingQuoteService(),
                    quoteMetaService: FailingQuoteMetaService()
                )
            )
        ]
    }
}

#if os(iOS)
#Preview("Live") {
    let scenario = QuotePreviewScenario.allCases[0]
    QuoteAppRootView(title: scenario.title, container: scenario.container)
}

#Preview("Preview") {
    let scenario = QuotePreviewScenario.allCases[1]
    QuoteAppRootView(title: scenario.title, container: scenario.container)
}

#Preview("Failure") {
    let scenario = QuotePreviewScenario.allCases[2]
    QuoteAppRootView(title: scenario.title, container: scenario.container)
}

#Preview("Matrix") {
    QuotePreviewMatrixView()
}
#endif

@main
struct PreviewInjectionExampleMain {
    static func main() {
        let liveScenario = QuotePreviewScenario.allCases[0]
        _ = QuoteAppRootView(title: liveScenario.title, container: liveScenario.container)
        _ = QuotePreviewMatrixView()
    }
}
