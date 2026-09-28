import Foundation
import Testing

@Suite("Ownership policy documentation contracts")
struct OwnershipPolicyDocumentationTests {
    @Test("Every validation guide retains mandatory local ownership-cycle checks")
    func localizedValidationGuidesPreserveOwnershipChecks() throws {
        let claims = [
            ("Validation.md", "Local ownership cycles are always rejected"),
            ("ko.lproj/Validation.md", "로컬 소유권 순환은 항상 거부됩니다"),
            ("ja.lproj/Validation.md", "ローカルの所有権循環は常に拒否されます"),
            ("zh-Hans.lproj/Validation.md", "本地所有权循环始终会被拒绝"),
            ("es.lproj/Validation.md", "Los ciclos locales de propiedad siempre se rechazan"),
            ("de.lproj/Validation.md", "Lokale Besitzzyklen werden immer abgelehnt"),
            ("ru.lproj/Validation.md", "Локальные циклы владения всегда отклоняются"),
        ]
        for (path, claim) in claims {
            let document = try normalizedDocument("Sources/InnoDI/InnoDI.docc/\(path)")
            #expect(document.contains(claim), "Missing ownership invariant in \(path)")
            #expect(document.contains("validateDAG: false"))
        }
    }

    @Test("Agent and policy guidance never recommend deferred wrappers as cycle escapes")
    func guidancePreservesOwnershipChecks() throws {
        let guidance = try normalizedDocument("CLAUDE.md")
        #expect(guidance.contains("Local ownership cycles are always rejected"))
        #expect(!guidance.contains("validation plus the macro's local cycle"))

        let policy = try normalizedDocument("Sources/InnoDI/InnoDI.docc/PolicyBoundaries.md")
        #expect(policy.contains("Local ownership cycles are always rejected"))
        #expect(policy.contains("defer construction but do not break ownership cycles"))
        #expect(!policy.contains("excluded from hard cycle detection"))
        #expect(!policy.contains("breaking cycles with deferred wrappers"))

        let workflow = try normalizedDocument(".github/workflows/macro-tests.yml")
        #expect(!workflow.contains("breaking cycle escape"))
    }

    private func normalizedDocument(_ path: String) throws -> String {
        try String(contentsOf: packageRootURL().appendingPathComponent(path), encoding: .utf8)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
