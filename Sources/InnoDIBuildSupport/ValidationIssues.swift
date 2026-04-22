import Foundation

/// Structured severity used by build-stage validation issues.
package enum ValidationIssueSeverity: String, Codable, Equatable, Sendable {
    case error
    case warning
    case note
}

/// Source location attached to a structured validation issue or note.
package struct ValidationIssueLocation: Codable, Equatable, Sendable {
    package let filePath: String
    package let line: Int
    package let column: Int
}

/// Supplementary context attached to a structured validation issue.
package struct ValidationIssueNote: Codable, Equatable, Sendable {
    package let message: String
    package let location: ValidationIssueLocation?

    package init(message: String, location: ValidationIssueLocation? = nil) {
        self.message = message
        self.location = location
    }
}

/// Structured validation failure emitted by build-support validators.
///
/// These issues are rendered both as stderr for failing builds and as Markdown
/// sections inside coordinator metrics artifacts.
package struct ValidationIssue: Codable, Equatable, Sendable {
    package let code: String
    package let severity: ValidationIssueSeverity
    package let message: String
    package let location: ValidationIssueLocation
    package let notes: [ValidationIssueNote]
    package let remediation: String?
    package let metadata: [String: String]

    package init(
        code: String,
        severity: ValidationIssueSeverity,
        message: String,
        location: ValidationIssueLocation,
        notes: [ValidationIssueNote] = [],
        remediation: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.code = code
        self.severity = severity
        self.message = message
        self.location = location
        self.notes = notes
        self.remediation = remediation
        self.metadata = metadata
    }
}

/// Aggregated result from a build-support validator pass.
package struct ValidationIssueReport: Codable, Equatable, Sendable {
    package let issues: [ValidationIssue]

    package init(issues: [ValidationIssue]) {
        self.issues = issues
    }

    package var hasFailures: Bool {
        issues.contains { $0.severity == .error }
    }

    package func asCommandResult() -> ValidationCommandResult? {
        guard hasFailures else {
            return nil
        }

        let failingIssues = issues.filter { $0.severity == .error }
        let stderr = ValidationIssueRenderer.renderStderr(issues: failingIssues)
        return ValidationCommandResult(exitCode: 1, stdout: "", stderr: stderr)
    }
}

/// Shared renderer for turning structured issues into stderr and Markdown
/// outputs.
package enum ValidationIssueRenderer {
    package static func renderStderr(issues: [ValidationIssue]) -> String {
        guard !issues.isEmpty else {
            return ""
        }

        return issues
            .map(renderStderr(issue:))
            .joined(separator: "\n") + "\n"
    }

    package static func renderMarkdown(issues: [ValidationIssue]) -> String {
        guard !issues.isEmpty else {
            return "## Build Issues\n\nNo structured build issues were emitted.\n"
        }

        var lines: [String] = ["## Build Issues", ""]
        for issue in issues {
            lines.append("### `[\(sanitizeInline(issue.code))]` \(sanitizeInline(issue.message))")
            lines.append("")
            lines.append("- Severity: `\(sanitizeInline(issue.severity.rawValue))`")
            lines.append("- Location: `\(renderLocation(issue.location))`")
            if let remediation = issue.remediation {
                lines.append("- Remediation: \(sanitizeInline(remediation))")
            }
            if !issue.metadata.isEmpty {
                for key in issue.metadata.keys.sorted() {
                    lines.append("- \(sanitizeInline(key)): `\(sanitizeInline(issue.metadata[key] ?? ""))`")
                }
            }
            for note in issue.notes {
                if let location = note.location {
                    lines.append("- Note: \(sanitizeInline(note.message)) (`\(renderLocation(location))`)")
                } else {
                    lines.append("- Note: \(sanitizeInline(note.message))")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func renderStderr(issue: ValidationIssue) -> String {
        var lines: [String] = [
            "\(renderLocation(issue.location)): \(sanitizeInline(issue.severity.rawValue)): [\(sanitizeInline(issue.code))] \(sanitizeInline(issue.message))"
        ]

        for note in issue.notes {
            if let location = note.location {
                lines.append("\(renderLocation(location)): note: \(sanitizeInline(note.message))")
            } else {
                lines.append("note: \(sanitizeInline(note.message))")
            }
        }

        if let remediation = issue.remediation {
            lines.append("note: Remediation: \(sanitizeInline(remediation))")
        }

        return lines.joined(separator: "\n")
    }

    private static func renderLocation(_ location: ValidationIssueLocation) -> String {
        "\(sanitizeInline(location.filePath)):\(location.line):\(location.column)"
    }

    private static func sanitizeInline(_ text: String) -> String {
        let sanitizedScalars = text.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
        }
        return sanitizedScalars
            .joined()
            .replacingOccurrences(of: "`", with: "'")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
