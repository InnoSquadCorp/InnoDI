//
//  InnoDI-DeferredAliasScan / main.swift
//
//  Workspace-wide scanner for `typealias` declarations that rename
//  `Lazy<T>` or `Provider<T>`. The macro plugin's same-file
//  `DILazyProviderAliasCheck` already warns when the alias lives in the
//  same file as the factory parameter, but a cross-file alias silently
//  behaves as a hard edge — the macro's canonical-identifier detection
//  never recognizes the renamed wrapper, and cycle escape stops working.
//
//  This executable surfaces those cross-file findings so PRs can audit
//  the canonical-identifier convention without the macro itself growing
//  workspace awareness. It is informational by default; consumers can
//  treat any finding as a release blocker by checking the JSON output.
//

import Foundation
import InnoDIWorkspaceAnalysis

struct ScanArguments {
    var rootPath: String
    var jsonPath: String?
}

enum ScanArgumentError: LocalizedError {
    case missingValue(option: String)
    case unknownOption(String)

    var errorDescription: String? {
        switch self {
        case let .missingValue(option):
            return "Option \(option) requires a value."
        case let .unknownOption(option):
            return "Unknown option \(option)."
        }
    }
}

func parseArguments() throws -> ScanArguments {
    var rootPath = FileManager.default.currentDirectoryPath
    var jsonPath: String?
    let argv = Array(CommandLine.arguments.dropFirst())
    var index = 0

    func requireValue(for option: String) throws -> String {
        guard index + 1 < argv.count else {
            throw ScanArgumentError.missingValue(option: option)
        }
        return argv[index + 1]
    }

    while index < argv.count {
        let option = argv[index]
        switch option {
        case "--root":
            rootPath = try requireValue(for: option)
            index += 2
        case "--json":
            jsonPath = try requireValue(for: option)
            index += 2
        case "-h", "--help":
            FileHandle.standardOutput.write(Data("""
            Usage: InnoDI-DeferredAliasScan [--root <path>] [--json <path>]

            Scans the workspace for `typealias` declarations that rename
            `Lazy<T>` or `Provider<T>`. Cross-file aliases silently disable
            the macro's canonical-identifier detection of deferred wrappers,
            so this scanner reports them as informational findings.

            Options:
              --root <path>   Workspace root (default: current directory)
              --json <path>   Write a JSON report to <path>

            Exit codes:
              0   Scan completed (with or without findings)
              1   Scan failed (workspace unreadable, invalid root, etc.)
              2   Argument parsing failed

            """.utf8))
            Foundation.exit(0)
        default:
            throw ScanArgumentError.unknownOption(option)
        }
    }

    return ScanArguments(rootPath: rootPath, jsonPath: jsonPath)
}

struct DeferredAliasReport: Encodable {
    struct Finding: Encodable {
        let kind: String
        let aliasName: String
        let relativePath: String
        let line: Int
        let column: Int
    }

    let workspaceRoot: String
    let totalFindings: Int
    let lazyFindings: Int
    let providerFindings: Int
    let findings: [Finding]
}

func renderMarkdown(report: DeferredAliasReport) -> String {
    var lines: [String] = [
        "### InnoDI deferred-wrapper alias scan",
        "",
        "Workspace root: `\(report.workspaceRoot)`",
        "",
    ]
    if report.totalFindings == 0 {
        lines.append(
            "No `typealias` declarations rename `Lazy<T>` or `Provider<T>` anywhere "
            + "in the workspace. Cross-file detection is clean."
        )
        return lines.joined(separator: "\n") + "\n"
    }

    lines.append(
        "Found **\(report.totalFindings)** typealias(es) that rename a deferred "
        + "wrapper (\(report.lazyFindings) `Lazy<T>`, "
        + "\(report.providerFindings) `Provider<T>`):"
    )
    lines.append("")
    lines.append("| Kind | Alias | Location |")
    lines.append("|---|---|---|")
    for finding in report.findings {
        lines.append(
            "| `\(finding.kind)` | `\(finding.aliasName)` | "
            + "`\(finding.relativePath):\(finding.line):\(finding.column)` |"
        )
    }
    lines.append("")
    lines.append(
        "These aliases prevent the macro's canonical-identifier detection from "
        + "recognising soft edges across files. At factory-parameter sites, prefer "
        + "spelling `Lazy<T>` / `Provider<T>` (or `InnoDI.Lazy<T>` / "
        + "`InnoDI.Provider<T>`) directly so cycle escape continues to work."
    )
    return lines.joined(separator: "\n") + "\n"
}

do {
    let arguments = try parseArguments()
    let snapshot = try loadWorkspaceSourceSnapshot(rootPath: arguments.rootPath)
    let findings = scanDeferredWrapperAliases(in: snapshot)

    let report = DeferredAliasReport(
        workspaceRoot: arguments.rootPath,
        totalFindings: findings.count,
        lazyFindings: findings.filter { $0.kind == .lazy }.count,
        providerFindings: findings.filter { $0.kind == .provider }.count,
        findings: findings.map {
            DeferredAliasReport.Finding(
                kind: $0.kind.rawValue,
                aliasName: $0.aliasName,
                relativePath: $0.relativePath,
                line: $0.line,
                column: $0.column
            )
        }
    )

    let markdown = renderMarkdown(report: report)
    FileHandle.standardOutput.write(Data(markdown.utf8))

    if let jsonPath = arguments.jsonPath {
        let url = URL(fileURLWithPath: jsonPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.outputFormatting.insert(.withoutEscapingSlashes)
        let data = try encoder.encode(report)
        try data.write(to: url)
    }
} catch let error as ScanArgumentError {
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    Foundation.exit(2)
} catch {
    FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
    Foundation.exit(1)
}
