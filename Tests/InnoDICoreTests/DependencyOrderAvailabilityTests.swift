import Testing

@testable import InnoDICore

@Suite("Dependency-order indexed availability")
struct DependencyOrderAvailabilityTests {
    @Test("Forward policy admits only same-stage shared construction")
    func forwardScopeMatrix() {
        let index = DependencyAvailabilityIndex(members: [
            .init(name: "sync", kind: .synchronousShared),
            .init(name: "async", kind: .asynchronousShared),
            .init(name: "laterSync", kind: .synchronousShared),
            .init(name: "laterAsync", kind: .asynchronousShared),
            .init(name: "transient", kind: .transient),
            .init(name: "input", kind: .input),
        ])
        #expect(index.availableNames(forMemberAt: 0, allowForwardSharedReferences: true)
            == ["sync", "laterSync", "input"])
        #expect(index.availableNames(forMemberAt: 1, allowForwardSharedReferences: true)
            == ["sync", "async", "laterSync", "laterAsync", "input"])
        #expect(index.availableNames(forMemberAt: 4, allowForwardSharedReferences: true) == index.knownNames)
        #expect(index.availableNames(forMemberAt: 5, allowForwardSharedReferences: true).isEmpty)
        #expect(index.status(of: "unknown", forMemberAt: -1, allowForwardSharedReferences: true) == .unknown)
        #expect(index.status(of: "input", forMemberAt: 6, allowForwardSharedReferences: true) == .unavailable)
        #expect(index.availableNames(forMemberAt: -1, allowForwardSharedReferences: true).isEmpty)
        // The default retains the prior declaration-order contract.
        #expect(index.availableNames(forMemberAt: 0) == ["input"])
        #expect(index.availableNames(forMemberAt: 1) == ["sync", "laterSync", "input"])
    }

    @Test("Duplicate-name recovery keeps union scope semantics")
    func duplicateNames() {
        let index = DependencyAvailabilityIndex(members: [
            .init(name: "consumer", kind: .synchronousShared),
            .init(name: "dependency", kind: .transient),
            .init(name: "dependency", kind: .asynchronousShared),
            .init(name: "dependency", kind: .synchronousShared),
        ])
        #expect(index.status(of: "dependency", forMemberAt: 0) == .unavailable)
        #expect(index.status(of: "dependency", forMemberAt: 0, allowForwardSharedReferences: true) == .available)
    }
}
