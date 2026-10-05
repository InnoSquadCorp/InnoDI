import InnoDI
import Testing

@Suite("Explicit preparation readiness")
struct PreparationReadinessTests {
    @Test("Ready report succeeds and every non-ready disposition preserves the exact report",
          arguments: DIAsyncPreparationEntry.Disposition.allPreparedTestCases)
    func check(disposition: DIAsyncPreparationEntry.Disposition) throws {
        let state: DIAsyncProviderStatus.State = disposition == .ready ? .ready : .failed
        let report = DIAsyncPreparationReport(selectedProviderIDs: ["service"], entries: [
            DIAsyncPreparationEntry(providerID: "service", status: .init(providerID: "service", generation: 3, state: state),
                                    disposition: disposition, blockingDependencies: disposition == .blocked ? ["upstream"] : [])
        ])
        if disposition == .ready {
            try report.requireReady()
        } else {
            #expect(throws: DIAsyncPreparationFailure(report: report)) { try report.requireReady() }
        }
    }
}

private extension DIAsyncPreparationEntry.Disposition {
    static var allPreparedTestCases: [Self] { [.ready, .failed, .blocked, .running, .cancelled, .closed] }
}
