import Testing

@testable import PreviewInjectionExample

@Suite("PreviewInjectionExample behavior")
struct PreviewInjectionExampleTests {
    @Test("Quote model loads quote and byline")
    @MainActor
    func quoteModelLoadsSuccessState() async throws {
        let model = QuoteFeatureModel()
        model.load(
            quoteService: DelayedQuoteService(text: "Loaded quote", delayMilliseconds: 0),
            quoteMetaService: DelayedQuoteMetaService(text: "Loaded byline", delayMilliseconds: 0)
        )

        try await waitUntilQuoteLoaded(model)

        guard case let .loaded(quote, byline) = model.phase else {
            Issue.record("Expected loaded quote state.")
            return
        }
        #expect(quote == "Loaded quote")
        #expect(byline == "Loaded byline")
    }

    @Test("Quote model failure is recoverable with retry")
    @MainActor
    func quoteModelFailsAndRecovers() async throws {
        let model = QuoteFeatureModel()
        model.load(
            quoteService: FailingQuoteService(),
            quoteMetaService: FailingQuoteMetaService()
        )
        try await waitUntilQuoteFailed(model)

        guard case let .failed(message) = model.phase else {
            Issue.record("Expected failed quote phase.")
            return
        }
        #expect(message.contains("Preview services failed"))

        model.load(
            quoteService: DelayedQuoteService(text: "Recovered quote", delayMilliseconds: 0),
            quoteMetaService: DelayedQuoteMetaService(text: "Recovered byline", delayMilliseconds: 0)
        )
        try await waitUntilQuoteLoaded(model)

        guard case let .loaded(quote, byline) = model.phase else {
            Issue.record("Expected loaded phase after retry.")
            return
        }
        #expect(quote == "Recovered quote")
        #expect(byline == "Recovered byline")
    }

    @Test("Quote model cancellation leaves loading phase untouched")
    @MainActor
    func quoteModelCancelPreventsTerminalWrite() async throws {
        let model = QuoteFeatureModel()
        model.load(
            quoteService: DelayedQuoteService(text: "Slow quote", delayMilliseconds: 150),
            quoteMetaService: DelayedQuoteMetaService(text: "Slow byline", delayMilliseconds: 150)
        )
        model.cancel()
        try await Task.sleep(for: .milliseconds(220))

        guard case .loading = model.phase else {
            Issue.record("Expected loading phase to remain after cancellation.")
            return
        }
    }

    @Test("Preview scenarios expose live preview and failure matrix inputs")
    @MainActor
    func previewScenariosExposeMatrixInputs() {
        #expect(QuotePreviewScenario.allCases.count == 3)

        let titles = QuotePreviewScenario.allCases.map(\.title)
        let featureRootView: Any = QuoteFeatureRootView(container: QuotePreviewScenario.allCases[0].container)
        #expect(titles == ["Live", "Preview", "Failure"])

        #expect(QuotePreviewScenario.allCases[0].container.quoteService is DelayedQuoteService)
        #expect(QuotePreviewScenario.allCases[1].container.quoteService is DelayedQuoteService)
        #expect(QuotePreviewScenario.allCases[2].container.quoteService is FailingQuoteService)
        #expect(featureRootView is QuoteFeatureRootView)
    }
}

@MainActor
private func waitUntilQuoteLoaded(_ model: QuoteFeatureModel) async throws {
    for _ in 0..<20 {
        if case .loaded = model.phase {
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("Timed out waiting for loaded quote phase.")
}

@MainActor
private func waitUntilQuoteFailed(_ model: QuoteFeatureModel) async throws {
    for _ in 0..<20 {
        if case .failed = model.phase {
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("Timed out waiting for failed quote phase.")
}
