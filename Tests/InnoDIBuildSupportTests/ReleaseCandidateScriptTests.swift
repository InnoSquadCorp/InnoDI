import Foundation
import Testing

@Suite("Release candidate script contracts")
struct ReleaseCandidateScriptTests {
    @Test("Valid release metadata passes without creating a tag")
    func validCandidatePassesWithoutCreatingTag() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }

        let result = try fixture.run()

        #expect(result.exitCode == 0)
        #expect(result.output.contains("Release candidate metadata validated"))
        #expect(try fixture.tagNames().isEmpty)
    }

    @Test("Repository root defaults to the validator's repository")
    func rootDefaultsToScriptRepository() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }

        let result = try fixture.runUsingDefaultRoot()

        #expect(result.exitCode == 0)
        #expect(result.output.contains("Release candidate metadata validated"))
    }

    @Test("Alternate breaking or behavior heading is accepted")
    func alternateBreakingHeadingIsAccepted() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            sections: [
                (fixture.version, ReleaseCandidateScriptFixture.alternateReleaseBody),
            ]
        )

        let result = try fixture.run()

        #expect(result.exitCode == 0)
    }

    @Test("Release metadata accepts CRLF line endings")
    func crlfReleaseMetadataIsAccepted() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.convertReleasingToCRLF()

        let result = try fixture.run()

        #expect(result.exitCode == 0)
    }

    @Test(
        "Only stable unprefixed SemVer without leading zeroes is accepted",
        arguments: [
            "v5.0.0",
            "05.0.0",
            "5.00.0",
            "5.0.00",
            "5.0",
            "5.0.0-rc.1",
            "5.0.0+build.1",
        ]
    )
    func invalidVersionIsRejected(_ version: String) throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }

        let result = try fixture.run(version: version)

        #expect(result.exitCode != 0)
        #expect(result.output.contains("stable, unprefixed semantic version"))
    }

    @Test("Commit SHA must be full lowercase hexadecimal")
    func invalidCommitSHAIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }

        let result = try fixture.run(
            commitSHA: String(repeating: "A", count: 40)
        )

        #expect(result.exitCode != 0)
        #expect(result.output.contains("40 lowercase hexadecimal"))
    }

    @Test("Version and commit SHA options are required")
    func releaseIdentityOptionsAreRequired() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }

        let missingVersion = try fixture.runRaw(arguments: [
            "--root", fixture.rootURL.path,
            "--commit-sha", fixture.commitSHA,
        ])
        let missingCommit = try fixture.runRaw(arguments: [
            "--root", fixture.rootURL.path,
            "--version", fixture.version,
        ])

        #expect(missingVersion.exitCode != 0)
        #expect(missingVersion.output.contains("--version is required"))
        #expect(missingCommit.exitCode != 0)
        #expect(missingCommit.output.contains("--commit-sha is required"))
    }

    @Test("Requested commit must equal Git HEAD")
    func mismatchedHeadIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }

        let result = try fixture.run(
            commitSHA: String(repeating: "0", count: 40)
        )

        #expect(result.exitCode != 0)
        #expect(result.output.contains("does not match Git HEAD"))
    }

    @Test("Latest stable release line must exactly match the candidate")
    func mismatchedLatestStableLineIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: "4.3.0",
            sections: [
                (fixture.version, ReleaseCandidateScriptFixture.canonicalReleaseBody),
            ]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("exactly one line"))
    }

    @Test("Candidate version cannot remain the current unreleased train")
    func candidateVersionCannotRemainUnreleased() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            currentDevelopmentTrain: fixture.version,
            sections: [
                (fixture.version, ReleaseCandidateScriptFixture.canonicalReleaseBody),
            ]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("current unreleased train"))
    }

    @Test("Release candidates cannot retain an Unreleased section")
    func unreleasedSectionIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            sections: [
                (fixture.version, ReleaseCandidateScriptFixture.canonicalReleaseBody),
                ("Unreleased", ReleaseCandidateScriptFixture.canonicalReleaseBody),
            ]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("cannot contain a '## Unreleased' section"))
    }

    @Test("Candidate release section is required")
    func missingReleaseSectionIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            sections: [
                ("4.3.0", ReleaseCandidateScriptFixture.canonicalReleaseBody),
            ]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("exactly one '## \(fixture.version)' section"))
    }

    @Test("Candidate release section must be unique")
    func duplicateReleaseSectionIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            sections: [
                (fixture.version, "- First"),
                (fixture.version, "- Duplicate"),
            ]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("exactly one '## \(fixture.version)' section"))
    }

    @Test("Candidate release section must contain content")
    func emptyReleaseSectionIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            sections: [
                (fixture.version, ""),
                ("4.3.0", "- Previous release"),
            ]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("must be nonempty"))
    }

    @Test("Highlights subsection is required")
    func missingHighlightsIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            sections: [(fixture.version, """
                ### Breaking and Behavior Changes

                - Validation is now strict.

                ### Upgrade Actions

                - Complete the release notes.
                """)]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("exactly one '### Highlights' subsection"))
    }

    @Test("Highlights subsection must be unique")
    func duplicateHighlightsIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            sections: [(fixture.version, """
                ### Highlights

                - First highlight.

                ### Highlights

                - Duplicate highlight.

                ### Breaking and Behavior Changes

                - Validation is now strict.

                ### Upgrade Actions

                - Complete the release notes.
                """)]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("exactly one '### Highlights' subsection"))
    }

    @Test("Highlights subsection requires substantive content")
    func emptyHighlightsIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            sections: [(fixture.version, """
                ### Highlights

                ### Breaking and Behavior Changes

                - Validation is now strict.

                ### Upgrade Actions

                - Complete the release notes.
                """)]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("'### Highlights' must contain non-placeholder content"))
    }

    @Test("Placeholder release-note content is rejected")
    func placeholderContentIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            sections: [(fixture.version, """
                ### Highlights

                - Ready

                ### Breaking and Behavior Changes

                - Validation is now strict.

                ### Upgrade Actions

                - Complete the release notes.
                """)]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("'### Highlights' must contain non-placeholder content"))
    }

    @Test("Breaking or behavior changes subsection is required")
    func missingBreakingChangesIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            sections: [(fixture.version, """
                ### Highlights

                - Added validation.

                ### Upgrade Actions

                - Complete the release notes.
                """)]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("exactly one breaking or behavior changes subsection"))
    }

    @Test("Breaking or behavior changes subsection must be unique")
    func duplicateBreakingChangesIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            sections: [(fixture.version, """
                ### Highlights

                - Added validation.

                ### Breaking and Behavior Changes

                - First behavior change.

                ### Breaking and Behavior Changes

                - Duplicate behavior change.

                ### Upgrade Actions

                - Complete the release notes.
                """)]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("exactly one breaking or behavior changes subsection"))
    }

    @Test("Both accepted breaking headings cannot appear together")
    func bothBreakingHeadingsAreRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            sections: [(fixture.version, """
                ### Highlights

                - Added validation.

                ### Breaking and Behavior Changes

                - First behavior change.

                ### Breaking or Behavior Changes

                - Duplicate behavior change.

                ### Upgrade Actions

                - Complete the release notes.
                """)]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("exactly one breaking or behavior changes subsection"))
    }

    @Test("Breaking or behavior changes requires substantive content")
    func emptyBreakingChangesIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            sections: [(fixture.version, """
                ### Highlights

                - Added validation.

                ### Breaking and Behavior Changes

                ### Upgrade Actions

                - Complete the release notes.
                """)]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("breaking or behavior changes subsection must contain non-placeholder content"))
    }

    @Test("Upgrade actions subsection is required")
    func missingUpgradeActionsIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            sections: [(fixture.version, """
                ### Highlights

                - Added validation.

                ### Breaking and Behavior Changes

                - Validation is now strict.
                """)]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("exactly one '### Upgrade Actions' subsection"))
    }

    @Test("Upgrade actions subsection must be unique")
    func duplicateUpgradeActionsIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            sections: [(fixture.version, """
                ### Highlights

                - Added validation.

                ### Breaking and Behavior Changes

                - Validation is now strict.

                ### Upgrade Actions

                - First upgrade action.

                ### Upgrade Actions

                - Duplicate upgrade action.
                """)]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("exactly one '### Upgrade Actions' subsection"))
    }

    @Test("Upgrade actions subsection requires substantive content")
    func emptyUpgradeActionsIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            sections: [(fixture.version, """
                ### Highlights

                - Added validation.

                ### Breaking and Behavior Changes

                - Validation is now strict.

                ### Upgrade Actions
                """)]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("'### Upgrade Actions' must contain non-placeholder content"))
    }

    @Test("Required headings in another release section do not count")
    func headingsInOtherReleaseSectionsDoNotCount() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            sections: [
                (fixture.version, "- Candidate summary without required subsections."),
                ("4.3.0", ReleaseCandidateScriptFixture.canonicalReleaseBody),
            ]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("exactly one '### Highlights' subsection (found 0)"))
    }

    @Test("Unknown third-level headings end the active release subsection")
    func unknownHeadingCannotDonateContent() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReleasing(
            latestVersion: fixture.version,
            sections: [(fixture.version, """
                ### Highlights

                ### Internal Notes

                - This detail belongs to the unknown subsection.

                ### Breaking and Behavior Changes

                - Validation is now strict.

                ### Upgrade Actions

                - Complete the release notes.
                """)]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("'### Highlights' must contain non-placeholder content"))
    }

    @Test("Every README dependency must use the candidate version")
    func staleReadmeVersionIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReadme(
            named: "README.ja.md",
            dependencyVersions: ["4.3.0"]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("README.ja.md must use"))
        #expect(result.output.contains("from: \"\(fixture.version)\""))
    }

    @Test("Every README must contain exactly one InnoDI dependency")
    func duplicateReadmeDependencyIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReadme(
            named: "README.ru.md",
            dependencyVersions: [fixture.version, fixture.version]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("README.ru.md must contain exactly one"))
    }

    @Test("All seven known README variants are required")
    func missingReadmeVariantIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try FileManager.default.removeItem(
            at: fixture.rootURL.appendingPathComponent("README.zh-Hans.md")
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("missing README variant: README.zh-Hans.md"))
    }
}

private struct ReleaseCandidateScriptResult {
    let exitCode: Int32
    let output: String
}

private struct ReleaseCandidateScriptFixture {
    static let canonicalReleaseBody = """
        ### Highlights

        - Added strict release-note validation.

        ### Breaking and Behavior Changes

        - Release candidates now require structured notes.

        ### Upgrade Actions

        - Complete every required subsection before publication.
        """

    static let alternateReleaseBody = """
        ### Highlights

        - Added strict release-note validation.

        ### Breaking or Behavior Changes

        - Release candidates now require structured notes.

        ### Upgrade Actions

        - Complete every required subsection before publication.
        """

    static let readmeNames = [
        "README.md",
        "README.ko.md",
        "README.ja.md",
        "README.zh-Hans.md",
        "README.de.md",
        "README.es.md",
        "README.ru.md",
    ]

    let rootURL: URL
    let version: String
    let commitSHA: String

    init(version: String = "5.0.0") throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "InnoDI-ReleaseCandidateScriptTests-\(UUID().uuidString)",
                isDirectory: true
            )

        do {
            try FileManager.default.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true
            )
            try Self.writeReleasing(
                at: rootURL,
                latestVersion: version,
                sections: [(version, Self.canonicalReleaseBody)]
            )
            for readmeName in Self.readmeNames {
                try Self.writeReadme(
                    at: rootURL,
                    named: readmeName,
                    dependencyVersions: [version]
                )
            }

            _ = try runCapturedCommand(
                executable: "/usr/bin/env",
                arguments: ["git", "-C", rootURL.path, "init", "-q"]
            )
            _ = try runCapturedCommand(
                executable: "/usr/bin/env",
                arguments: [
                    "git", "-C", rootURL.path,
                    "config", "user.name", "InnoDI Tests",
                ]
            )
            _ = try runCapturedCommand(
                executable: "/usr/bin/env",
                arguments: [
                    "git", "-C", rootURL.path,
                    "config", "user.email", "innodi-tests@example.invalid",
                ]
            )
            _ = try runCapturedCommand(
                executable: "/usr/bin/env",
                arguments: ["git", "-C", rootURL.path, "add", "."]
            )
            _ = try runCapturedCommand(
                executable: "/usr/bin/env",
                arguments: [
                    "git", "-C", rootURL.path,
                    "commit", "-q", "-m", "Create release fixture",
                ]
            )
            let headResult = try runCapturedCommand(
                executable: "/usr/bin/env",
                arguments: ["git", "-C", rootURL.path, "rev-parse", "HEAD"]
            )

            self.rootURL = rootURL
            self.version = version
            self.commitSHA = headResult.output.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        } catch {
            try? FileManager.default.removeItem(at: rootURL)
            throw error
        }
    }

    func run(
        version: String? = nil,
        commitSHA: String? = nil
    ) throws -> ReleaseCandidateScriptResult {
        try runValidator(
            at: packageRootURL()
                .appendingPathComponent("Tools/validate-release-candidate.sh"),
            includeRoot: true,
            version: version ?? self.version,
            commitSHA: commitSHA ?? self.commitSHA
        )
    }

    func runUsingDefaultRoot() throws -> ReleaseCandidateScriptResult {
        let toolsURL = rootURL.appendingPathComponent("Tools", isDirectory: true)
        try FileManager.default.createDirectory(
            at: toolsURL,
            withIntermediateDirectories: true
        )
        let copiedScriptURL = toolsURL.appendingPathComponent(
            "validate-release-candidate.sh"
        )
        try FileManager.default.copyItem(
            at: packageRootURL()
                .appendingPathComponent("Tools/validate-release-candidate.sh"),
            to: copiedScriptURL
        )

        return try runValidator(
            at: copiedScriptURL,
            includeRoot: false,
            version: version,
            commitSHA: commitSHA
        )
    }

    func runRaw(arguments: [String]) throws -> ReleaseCandidateScriptResult {
        let result = try runCapturedCommand(
            executable: "/bin/bash",
            arguments: [
                packageRootURL()
                    .appendingPathComponent("Tools/validate-release-candidate.sh")
                    .path,
            ] + arguments
        )
        return ReleaseCandidateScriptResult(
            exitCode: result.exitCode,
            output: result.output
        )
    }

    func writeReleasing(
        latestVersion: String,
        currentDevelopmentTrain: String? = nil,
        sections: [(version: String, body: String)]
    ) throws {
        try Self.writeReleasing(
            at: rootURL,
            latestVersion: latestVersion,
            currentDevelopmentTrain: currentDevelopmentTrain,
            sections: sections
        )
    }

    func writeReadme(
        named name: String,
        dependencyVersions: [String]
    ) throws {
        try Self.writeReadme(
            at: rootURL,
            named: name,
            dependencyVersions: dependencyVersions
        )
    }

    func convertReleasingToCRLF() throws {
        let releasingURL = rootURL.appendingPathComponent("RELEASING.md")
        let document = try String(contentsOf: releasingURL, encoding: .utf8)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        try document.write(
            to: releasingURL,
            atomically: true,
            encoding: .utf8
        )
    }

    func tagNames() throws -> [String] {
        let result = try runCapturedCommand(
            executable: "/usr/bin/env",
            arguments: ["git", "-C", rootURL.path, "tag", "--list"]
        )
        return result.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private func runValidator(
        at scriptURL: URL,
        includeRoot: Bool,
        version: String,
        commitSHA: String
    ) throws -> ReleaseCandidateScriptResult {
        var arguments = [scriptURL.path]
        if includeRoot {
            arguments += ["--root", rootURL.path]
        }
        arguments += [
            "--version", version,
            "--commit-sha", commitSHA,
        ]

        let result = try runCapturedCommand(
            executable: "/bin/bash",
            arguments: arguments
        )
        return ReleaseCandidateScriptResult(
            exitCode: result.exitCode,
            output: result.output
        )
    }

    private static func writeReleasing(
        at rootURL: URL,
        latestVersion: String,
        currentDevelopmentTrain: String? = nil,
        sections: [(version: String, body: String)]
    ) throws {
        var document = """
            # Releasing InnoDI

            Latest stable public release: `\(latestVersion)`

            """
        if let currentDevelopmentTrain {
            document += "Current development train: `\(currentDevelopmentTrain)` (unreleased)\n\n"
        }
        for section in sections {
            document += "## \(section.version)\n\n\(section.body)\n\n"
        }
        try document.write(
            to: rootURL.appendingPathComponent("RELEASING.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func writeReadme(
        at rootURL: URL,
        named name: String,
        dependencyVersions: [String]
    ) throws {
        let dependencies = dependencyVersions.map { version in
            """
                .package(
                    url: "https://github.com/InnoSquadCorp/InnoDI.git",
                    from: "\(version)"
                )
            """
        }
        let document = """
            # InnoDI

            ```swift
            let package = Package(
                dependencies: [
            \(dependencies.joined(separator: ",\n"))
                ]
            )
            ```
            """
        try document.write(
            to: rootURL.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }
}

private struct CapturedCommandResult {
    let exitCode: Int32
    let output: String
}

private func runCapturedCommand(
    executable: String,
    arguments: [String]
) throws -> CapturedCommandResult {
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CommandOutput-\(UUID().uuidString).log")
    _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: outputURL) }

    let outputHandle = try FileHandle(forWritingTo: outputURL)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = outputHandle
    process.standardError = outputHandle

    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "GIT_DIR")
    environment.removeValue(forKey: "GIT_WORK_TREE")
    process.environment = environment

    try process.run()
    process.waitUntilExit()
    try outputHandle.synchronize()
    try outputHandle.close()

    return CapturedCommandResult(
        exitCode: process.terminationStatus,
        output: try String(contentsOf: outputURL, encoding: .utf8)
    )
}
