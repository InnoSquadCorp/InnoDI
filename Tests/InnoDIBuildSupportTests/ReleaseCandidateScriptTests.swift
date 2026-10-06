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
        try fixture.writeChangelog(
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
        try fixture.convertChangelogToCRLF()

        let result = try fixture.run()

        #expect(result.exitCode == 0)
    }

    @Test("Validated metadata can be extracted with LF or CRLF line endings", arguments: [false, true])
    func validatedMetadataCanBeExtracted(crlf: Bool) throws {
        let fixture = try ReleaseCandidateScriptFixture(version: "6.0.0")
        defer { fixture.remove() }
        if crlf {
            try fixture.convertChangelogToCRLF()
        }

        let validation = try fixture.run()
        try #require(validation.exitCode == 0)
        let extraction = try fixture.extractNotes()
        #expect(extraction.exitCode == 0)
        #expect(extraction.output == "\n\(ReleaseCandidateScriptFixture.canonicalReleaseBody)\n")
        #expect(try fixture.tagNames().isEmpty)
    }

    @Test("6.x release requires RFC 0006 to be accepted")
    func acceptedRFC0006IsRequired() throws {
        let fixture = try ReleaseCandidateScriptFixture(version: "6.0.0")
        defer { fixture.remove() }

        let result = try fixture.run()

        #expect(result.exitCode == 0)
        #expect(result.output.contains("Release candidate metadata validated"))
    }

    @Test("6.x release rejects a pending RFC 0006 document")
    func pendingRFC0006DocumentIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture(version: "6.0.0")
        defer { fixture.remove() }
        try fixture.writeRFC0006(
            status: "Draft (promotion review)",
            indexStatus: "Accepted"
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(
            result.output.contains(
                "requires RFC 0006 to contain exactly one authoritative"
            )
        )
    }

    @Test("6.x release rejects a pending RFC 0006 index row")
    func pendingRFC0006IndexRowIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture(version: "6.0.0")
        defer { fixture.remove() }
        try fixture.writeRFC0006(
            status: "Accepted",
            indexStatus: "Draft (promotion review)"
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(
            result.output.contains(
                "requires the RFC index to contain exactly one Accepted RFC 0006 row"
            )
        )
    }

    @Test("6.x release rejects a duplicate RFC 0006 status")
    func duplicateRFC0006StatusIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture(version: "6.0.0")
        defer { fixture.remove() }
        try fixture.appendRFC0006Status("Accepted")

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(
            result.output.contains(
                "requires RFC 0006 to contain exactly one authoritative"
            )
        )
    }

    @Test("6.x release rejects a missing RFC 0006 document")
    func missingRFC0006DocumentIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture(version: "6.0.0")
        defer { fixture.remove() }
        try FileManager.default.removeItem(
            at: fixture.rootURL.appendingPathComponent(
                "docs/rfcs/0006-assisted-subgraphs-and-container-roles.md"
            )
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("6.x release requires RFC 0006:"))
    }

    @Test("7.x release requires RFC 0008 and RFC 0009 to be accepted")
    func acceptedRFC70IsRequired() throws {
        let fixture = try ReleaseCandidateScriptFixture(version: "7.0.0")
        defer { fixture.remove() }

        let result = try fixture.run()

        #expect(result.exitCode == 0)
        #expect(result.output.contains("Release candidate metadata validated"))
    }

    @Test("7.x release rejects a pending RFC 0008 or RFC 0009 document", arguments: ["0008", "0009"])
    func pendingRFC70DocumentIsRejected(number: String) throws {
        let fixture = try ReleaseCandidateScriptFixture(version: "7.0.0")
        defer { fixture.remove() }
        try fixture.writeRFC70(
            number == "0008" ? ReleaseCandidateScriptFixture.rfc0008 : ReleaseCandidateScriptFixture.rfc0009,
            status: "Draft (awaiting maintainer acceptance)",
            indexStatus: "Accepted"
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(
            result.output.contains(
                "7.x release requires RFC \(number) to contain exactly one authoritative"
            )
        )
    }

    @Test("7.x release rejects a pending RFC 0008 or RFC 0009 index row", arguments: ["0008", "0009"])
    func pendingRFC70IndexRowIsRejected(number: String) throws {
        let fixture = try ReleaseCandidateScriptFixture(version: "7.0.0")
        defer { fixture.remove() }
        try fixture.writeRFC70(
            number == "0008" ? ReleaseCandidateScriptFixture.rfc0008 : ReleaseCandidateScriptFixture.rfc0009,
            status: "Accepted",
            indexStatus: "Draft"
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(
            result.output.contains(
                "7.x release requires the RFC index to contain exactly one Accepted RFC \(number) row"
            )
        )
    }

    @Test("7.x release rejects a missing RFC 0009 document")
    func missingRFC0009DocumentIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture(version: "7.0.0")
        defer { fixture.remove() }
        try FileManager.default.removeItem(
            at: fixture.rootURL.appendingPathComponent(
                "docs/rfcs/0009-7.0-source-breaks.md"
            )
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("7.x release requires RFC 0009:"))
    }

    @Test("6.x release rejects a missing RFC index")
    func missingRFCIndexIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture(version: "6.0.0")
        defer { fixture.remove() }
        try FileManager.default.removeItem(
            at: fixture.rootURL.appendingPathComponent("docs/rfcs/README.md")
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("6.x release requires the RFC index:"))
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
        try fixture.writeChangelog(
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
        try fixture.writeChangelog(
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
        try fixture.writeChangelog(
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
        try fixture.writeChangelog(
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
        try fixture.writeChangelog(
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
        try fixture.writeChangelog(
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
        try fixture.writeChangelog(
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
        try fixture.writeChangelog(
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
        try fixture.writeChangelog(
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
        try fixture.writeChangelog(
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
        try fixture.writeChangelog(
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
        try fixture.writeChangelog(
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
        try fixture.writeChangelog(
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
        try fixture.writeChangelog(
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
        try fixture.writeChangelog(
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
        try fixture.writeChangelog(
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
        try fixture.writeChangelog(
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
        try fixture.writeChangelog(
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
        try fixture.writeChangelog(
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
            named: "README.ko.md",
            dependencyVersions: ["4.3.0"]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("README.ko.md must use"))
        #expect(result.output.contains("from: \"\(fixture.version)\""))
    }

    @Test("Every README must contain exactly one InnoDI dependency")
    func duplicateReadmeDependencyIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeReadme(
            named: "README.ko.md",
            dependencyVersions: [fixture.version, fixture.version]
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("README.ko.md must contain exactly one"))
    }

    @Test("The English and Korean README variants are required")
    func missingReadmeVariantIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try FileManager.default.removeItem(
            at: fixture.rootURL.appendingPathComponent("README.ko.md")
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("missing README variant: README.ko.md"))
    }

    @Test("English migration guide cannot describe the candidate train as unreleased")
    func unreleasedEnglishMigrationGuideIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeMigrationGuide(
            named: "Sources/InnoDI/InnoDI.docc/MigrationGuide.md",
            body: "## 4.x → 5.0 (unreleased)\n"
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("MigrationGuide.md still describes 5.0 as unreleased"))
    }

    @Test("Korean migration guide cannot describe the candidate train as unreleased")
    func unreleasedKoreanMigrationGuideIsRejected() throws {
        let fixture = try ReleaseCandidateScriptFixture()
        defer { fixture.remove() }
        try fixture.writeMigrationGuide(
            named: "Sources/InnoDI/InnoDI.docc/ko.lproj/MigrationGuide.md",
            body: "## 4.x → 5.0 (미출시)\n"
        )

        let result = try fixture.run()

        #expect(result.exitCode != 0)
        #expect(result.output.contains("ko.lproj/MigrationGuide.md still describes 5.0 as 미출시"))
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
            try Self.writeChangelog(
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
            try Self.writeMigrationGuide(
                at: rootURL,
                named: "Sources/InnoDI/InnoDI.docc/MigrationGuide.md",
                body: "## 4.x → \(Self.majorMinor(version))\n"
            )
            try Self.writeMigrationGuide(
                at: rootURL,
                named: "Sources/InnoDI/InnoDI.docc/ko.lproj/MigrationGuide.md",
                body: "## 4.x → \(Self.majorMinor(version))\n"
            )
            let requiredRFCs = Self.requiredRFCs(forMajor: version.split(separator: ".").first.map(String.init))
            for locale in ["", "ko.lproj/"] {
                for article in ["Overview", "OwnedContainers", "DIContainer", "Provide"] {
                    let body = article == "Overview"
                        ? (locale.isEmpty
                            ? "The latest stable release is \(version).\n"
                            : "최신 안정 릴리스는 \(version)입니다.\n")
                        : "Released API documentation for \(version).\n"
                    try Self.writeMigrationGuide(
                        at: rootURL,
                        named: "Sources/InnoDI/InnoDI.docc/\(locale)\(article).md",
                        body: body
                    )
                }
            }
            if !requiredRFCs.isEmpty {
                try Self.writeRFCs(
                    at: rootURL,
                    requiredRFCs.map { ($0, "Accepted", "Accepted") }
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

    func extractNotes() throws -> CapturedCommandResult {
        try runCapturedCommand(
            executable: "/bin/bash",
            arguments: [packageRootURL().appendingPathComponent("Tools/extract-release-notes.sh").path, version],
            currentDirectory: rootURL
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

    func writeChangelog(
        latestVersion: String,
        currentDevelopmentTrain: String? = nil,
        sections: [(version: String, body: String)]
    ) throws {
        try Self.writeChangelog(
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

    func writeMigrationGuide(named name: String, body: String) throws {
        try Self.writeMigrationGuide(at: rootURL, named: name, body: body)
    }

    func writeRFC0006(status: String, indexStatus: String) throws {
        try Self.writeRFCs(at: rootURL, [(Self.rfc0006, status, indexStatus)])
    }

    /// Rewrites the 7.0 RFCs, giving `changed` the statuses and keeping the
    /// other one accepted.
    func writeRFC70(
        _ changed: ReleaseRFC,
        status: String,
        indexStatus: String
    ) throws {
        try Self.writeRFCs(
            at: rootURL,
            [Self.rfc0008, Self.rfc0009].map { rfc in
                rfc == changed ? (rfc, status, indexStatus) : (rfc, "Accepted", "Accepted")
            }
        )
    }

    func appendRFC0006Status(_ status: String) throws {
        let rfcURL = rootURL.appendingPathComponent(
            "docs/rfcs/0006-assisted-subgraphs-and-container-roles.md"
        )
        var document = try String(contentsOf: rfcURL, encoding: .utf8)
        document += "\n- **Status**: \(status)\n"
        try document.write(to: rfcURL, atomically: true, encoding: .utf8)
    }

    func convertChangelogToCRLF() throws {
        let changelogURL = rootURL.appendingPathComponent("CHANGELOG.md")
        let document = try String(contentsOf: changelogURL, encoding: .utf8)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        try document.write(
            to: changelogURL,
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

    private static func writeChangelog(
        at rootURL: URL,
        latestVersion: String,
        currentDevelopmentTrain: String? = nil,
        sections: [(version: String, body: String)]
    ) throws {
        var document = """
            # Changelog

            Latest stable public release: `\(latestVersion)`

            """
        if let currentDevelopmentTrain {
            document += "Current development train: `\(currentDevelopmentTrain)` (unreleased)\n\n"
        }
        for section in sections {
            document += "## \(section.version)\n\n\(section.body)\n\n"
        }
        try document.write(
            to: rootURL.appendingPathComponent("CHANGELOG.md"),
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

    private static func writeMigrationGuide(
        at rootURL: URL,
        named name: String,
        body: String
    ) throws {
        let guideURL = rootURL.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: guideURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try body.write(to: guideURL, atomically: true, encoding: .utf8)
    }

    static let rfc0006 = ReleaseRFC(
        number: "0006",
        fileName: "0006-assisted-subgraphs-and-container-roles.md",
        title: "Assisted subgraphs and container roles"
    )
    static let rfc0008 = ReleaseRFC(
        number: "0008",
        fileName: "0008-async-on-demand-providers.md",
        title: "Asynchronous on-demand providers"
    )
    static let rfc0009 = ReleaseRFC(
        number: "0009",
        fileName: "0009-7.0-source-breaks.md",
        title: "7.0 source breaks"
    )

    private static func requiredRFCs(forMajor major: String?) -> [ReleaseRFC] {
        switch major {
        case "6": [rfc0006]
        case "7": [rfc0008, rfc0009]
        default: []
        }
    }

    private static func writeRFCs(
        at rootURL: URL,
        _ records: [(rfc: ReleaseRFC, status: String, indexStatus: String)]
    ) throws {
        let rfcDirectory = rootURL
            .appendingPathComponent("docs/rfcs", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rfcDirectory,
            withIntermediateDirectories: true
        )
        for record in records {
            try """
                # RFC \(record.rfc.number) — \(record.rfc.title)

                - **Status**: \(record.status)
                """.write(
                    to: rfcDirectory.appendingPathComponent(record.rfc.fileName),
                    atomically: true,
                    encoding: .utf8
                )
        }
        let rows = records.map { record in
            "| \(record.rfc.number) | [\(record.rfc.title)](\(record.rfc.fileName)) | \(record.indexStatus) |"
        }
        try ([
            "# RFC index",
            "",
            "| Number | Title | Status |",
            "|---|---|---|",
        ] + rows).joined(separator: "\n").write(
            to: rfcDirectory.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func majorMinor(_ version: String) -> String {
        version.split(separator: ".").prefix(2).joined(separator: ".")
    }
}

private struct ReleaseRFC: Equatable {
    let number: String
    let fileName: String
    let title: String
}

private struct CapturedCommandResult {
    let exitCode: Int32
    let output: String
}

private func runCapturedCommand(
    executable: String,
    arguments: [String],
    currentDirectory: URL? = nil
) throws -> CapturedCommandResult {
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CommandOutput-\(UUID().uuidString).log")
    _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: outputURL) }

    let outputHandle = try FileHandle(forWritingTo: outputURL)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
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
