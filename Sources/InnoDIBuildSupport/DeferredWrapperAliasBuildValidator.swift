import Foundation
import InnoDIWorkspaceAnalysis

/// Surfaces workspace-level `typealias` declarations that rename `Lazy<T>` or
/// `Provider<T>` so contributors learn that the macro plugin resolves
/// deferred-wrapper kinds by canonical identifier at the factory parameter
/// site. An alias declared in a different file from the consuming `@Provide`
/// is silently treated as a hard edge by the macro and re-introduces the
/// cycle the wrapper was meant to break.
///
/// The validator runs alongside the other build-support passes through
/// `ValidationCoordinator`. Findings are emitted as `warning` severity so a
/// build does not fail when an alias might be intentional sugar — they
/// surface in the structured metrics artifact and in stderr if the
/// coordinator is rendering warnings — but they do flag the most common
/// silent regression path the same-file lint rule cannot reach.
package enum DeferredWrapperAliasBuildValidator {
    package static func validate(rootPath: String) throws -> ValidationIssueReport {
        try validate(snapshot: loadWorkspaceSourceSnapshot(rootPath: rootPath))
    }

    package static func validate(snapshot: WorkspaceSourceSnapshot) -> ValidationIssueReport {
        let findings = scanDeferredWrapperAliases(in: snapshot)
        guard !findings.isEmpty else {
            return ValidationIssueReport(issues: [])
        }

        let issues = findings
            .map(makeIssue(from:))
            .sorted { lhs, rhs in
                if lhs.location.filePath != rhs.location.filePath { return lhs.location.filePath < rhs.location.filePath }
                if lhs.location.line != rhs.location.line { return lhs.location.line < rhs.location.line }
                return lhs.location.column < rhs.location.column
            }
        return ValidationIssueReport(issues: issues)
    }

    private static func makeIssue(from finding: DeferredWrapperAliasFinding) -> ValidationIssue {
        let wrapper = finding.kind == .lazy ? "Lazy" : "Provider"
        return ValidationIssue(
            code: "deferred-alias.workspace-finding",
            severity: .warning,
            message: "typealias '\(finding.aliasName)' renames \(wrapper)<...> at the workspace level. The macro resolves deferred-wrapper kinds by canonical identifier at the factory parameter site, so referencing this alias from another file is silently treated as a hard edge and re-introduces the cycle the wrapper was meant to break.",
            location: ValidationIssueLocation(
                filePath: finding.relativePath,
                line: finding.line,
                column: finding.column
            ),
            notes: [
                ValidationIssueNote(
                    message: "Use \(wrapper)<T> directly at the factory parameter site, or co-locate this typealias with the @Provide member that consumes it."
                )
            ],
            remediation: "Inline the wrapper at the factory parameter, or move the alias into the same file as the consuming @Provide.",
            metadata: [
                "aliasKind": finding.kind.rawValue,
                "aliasName": finding.aliasName
            ]
        )
    }
}
