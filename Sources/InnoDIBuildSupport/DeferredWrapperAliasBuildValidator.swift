import Foundation
import InnoDIWorkspaceAnalysis

/// Surfaces top-level `typealias` declarations that rename `Lazy<T>` or
/// `Provider<T>`. InnoDI classifies a factory parameter by its written
/// spelling and never resolves aliases, in any file, so a parameter typed
/// with such an alias is a hard edge rather than a deferred handle.
///
/// The validator runs alongside the other build-support passes through
/// `ValidationCoordinator`. Findings are emitted as `warning` severity so a
/// build does not fail when an alias might be intentional sugar — they
/// surface in the structured metrics artifact and in stderr if the
/// coordinator is rendering warnings. The macro-level alias check cannot
/// cover this case in a real build, because the compiler hands the macro
/// only the attached declaration.
///
/// Warnings are emitted unconditionally per coordinator invocation, so they
/// surface in the metrics artifact even when an upstream validator failure
/// (custom-init, semantic, or hierarchy) short-circuits the build. This is
/// intentional: an alias declared during a failing build is still a future
/// regression hazard, and the warning makes it visible alongside the
/// failure issues.
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
            message: "typealias '\(finding.aliasName)' renames \(wrapper)<...>. InnoDI classifies a factory parameter by its written spelling and never resolves aliases, so a parameter typed with this alias is a hard edge to the member of that name instead of a deferred handle, and the generated call usually fails to type-check.",
            location: ValidationIssueLocation(
                filePath: finding.relativePath,
                line: finding.line,
                column: finding.column
            ),
            notes: [
                ValidationIssueNote(
                    message: "Spell \(wrapper)<T> directly at the factory parameter. Moving the alias into the consuming file does not change how InnoDI reads it."
                )
            ],
            remediation: "Spell the wrapper directly at the factory parameter.",
            metadata: [
                "aliasKind": finding.kind.rawValue,
                "aliasName": finding.aliasName
            ]
        )
    }
}
