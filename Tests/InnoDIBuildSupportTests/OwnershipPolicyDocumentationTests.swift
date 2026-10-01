import Foundation
import Testing

@Suite("Ownership policy documentation contracts")
struct OwnershipPolicyDocumentationTests {
    @Test("Every maintained validation guide retains mandatory local ownership-cycle checks")
    func localizedValidationGuidesPreserveOwnershipChecks() throws {
        let claims = [
            ("Validation.md", "Local ownership cycles are always rejected"),
            ("ko.lproj/Validation.md", "로컬 소유권 순환은 항상 거부됩니다"),
        ]
        for (path, claim) in claims {
            let document = try normalizedDocument("Sources/InnoDI/InnoDI.docc/\(path)")
            #expect(document.contains(claim), "Missing ownership invariant in \(path)")
            #expect(document.contains("validateDAG: false"))
        }
    }

    @Test("Frozen translations hold only their notice page, so no stale guide can contradict the policy")
    func frozenTranslationsHoldOnlyNoticePages() throws {
        let catalog = packageRootURL().appendingPathComponent("Sources/InnoDI/InnoDI.docc")
        for language in ["ja", "zh-Hans", "es", "de", "ru"] {
            let contents = try FileManager.default
                .contentsOfDirectory(atPath: catalog.appendingPathComponent("\(language).lproj").path)
                .filter { !$0.hasPrefix(".") }
            #expect(contents == ["TranslationNotice-\(language).md"], "\(language).lproj holds \(contents)")
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
