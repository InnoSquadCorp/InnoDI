import Foundation

package enum ValidationIssueSeverity: String, Codable, Equatable, Sendable {
    case error
    case warning
    case note
}

package struct ValidationIssueLocation: Codable, Equatable, Sendable {
    package let filePath: String
    package let line: Int
    package let column: Int
}

package struct ValidationIssueNote: Codable, Equatable, Sendable {
    package let message: String
    package let location: ValidationIssueLocation?

    package init(message: String, location: ValidationIssueLocation? = nil) {
        self.message = message
        self.location = location
    }
}

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

package struct ValidationIssueReport: Codable, Equatable, Sendable {
    package let issues: [ValidationIssue]

    package init(issues: [ValidationIssue]) {
        self.issues = issues
    }

    package var hasFailures: Bool {
        !issues.isEmpty
    }

    package func asCommandResult() -> ValidationCommandResult? {
        guard hasFailures else {
            return nil
        }

        let stderr = ValidationIssueRenderer.renderStderr(issues: issues)
        return ValidationCommandResult(exitCode: 1, stdout: "", stderr: stderr)
    }
}

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
            lines.append("### `[\(issue.code)]` \(issue.message)")
            lines.append("")
            lines.append("- Severity: `\(issue.severity.rawValue)`")
            lines.append("- Location: `\(issue.location.filePath):\(issue.location.line):\(issue.location.column)`")
            if let remediation = issue.remediation {
                lines.append("- Remediation: \(remediation)")
            }
            if !issue.metadata.isEmpty {
                for key in issue.metadata.keys.sorted() {
                    lines.append("- \(key): `\(issue.metadata[key] ?? "")`")
                }
            }
            for note in issue.notes {
                if let location = note.location {
                    lines.append("- Note: \(note.message) (`\(location.filePath):\(location.line):\(location.column)`)")   
                } else {
                    lines.append("- Note: \(note.message)")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func renderStderr(issue: ValidationIssue) -> String {
        var lines: [String] = [
            "\(issue.location.filePath):\(issue.location.line):\(issue.location.column): \(issue.severity.rawValue): [\(issue.code)] \(issue.message)"
        ]

        for note in issue.notes {
            if let location = note.location {
                lines.append("\(location.filePath):\(location.line):\(location.column): note: \(note.message)")
            } else {
                lines.append("note: \(note.message)")
            }
        }

        if let remediation = issue.remediation {
            lines.append("note: Remediation: \(remediation)")
        }

        return lines.joined(separator: "\n")
    }
}
