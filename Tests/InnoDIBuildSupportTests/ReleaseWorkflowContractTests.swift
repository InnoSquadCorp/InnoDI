import Foundation
import Testing

@Suite("Release workflow contracts")
struct ReleaseWorkflowContractTests {
    private var workflow: String {
        get throws {
            try String(
                contentsOf: packageRootURL()
                    .appendingPathComponent(".github/workflows/release.yml"),
                encoding: .utf8
            )
        }
    }

    @Test("Release publication is manual and SHA-bound")
    func manualSHAOnlyTrigger() throws {
        let workflow = try workflow

        #expect(workflow.contains("on:\n  workflow_dispatch:"))
        #expect(!workflow.contains("\n  push:"))
        #expect(workflow.contains("ref: ${{ inputs.commit_sha }}"))
        #expect(workflow.contains("DISPATCH_REF: ${{ github.ref }}"))
        #expect(workflow.contains("DISPATCH_SHA: ${{ github.sha }}"))
    }

    @Test("External actions are pinned and checkouts retain no credentials")
    func pinnedActionsAndCredentiallessCheckouts() throws {
        let workflow = try workflow
        let actionPattern = try NSRegularExpression(
            pattern: #"(?m)^\s+uses: (?!\./)([^@\s]+)@([^\s]+)"#
        )
        let fullSHAPattern = try NSRegularExpression(
            pattern: #"^[0-9a-f]{40}$"#
        )
        let fullRange = NSRange(workflow.startIndex..., in: workflow)
        let matches = actionPattern.matches(in: workflow, range: fullRange)

        #expect(!matches.isEmpty)
        for match in matches {
            let revisionRange = try #require(
                Range(match.range(at: 2), in: workflow)
            )
            let revision = String(workflow[revisionRange])
            let range = NSRange(revision.startIndex..., in: revision)
            #expect(
                fullSHAPattern.firstMatch(in: revision, range: range) != nil,
                "External action revision must be a full SHA: \(revision)"
            )
        }

        #expect(!workflow.contains("persist-credentials: true"))
        #expect(workflow.components(separatedBy: "persist-credentials: false").count - 1 == 6)
    }

    @Test("Validation steps cannot access release credentials")
    func validationStepsAreTokenFree() throws {
        let workflow = try workflow
        let preflightValidator = try section(
            in: workflow,
            from: "      - name: Validate local release candidate",
            to: "      - name: Validate remote release anchor"
        )
        let stageValidator = try section(
            in: workflow,
            from: "      - name: Revalidate candidate and artifacts without credentials",
            to: "      - name: Require immutable release and tag policies"
        )
        let remoteAnchor = try section(
            in: workflow,
            from: "      - name: Validate remote release anchor",
            to: "  recovery-state:"
        )
        let releaseLookup = try section(
            in: workflow,
            from: "      - name: Validate exact release recovery state",
            to: "  release-gate:"
        )
        let policyCheck = try section(
            in: workflow,
            from: "      - name: Require immutable release and tag policies",
            to: "      - name: Stage annotated tag and draft release"
        )
        let stageJob = try section(
            in: workflow,
            from: "  stage-release:",
            to: "  exact-tag-consumer:"
        )
        let exactTagJob = try section(
            in: workflow,
            from: "  exact-tag-consumer:",
            to: "  publish-release:"
        )
        let publishJob = workflow[try #require(
            workflow.range(of: "  publish-release:")
        ).lowerBound...]

        #expect(try credentialIdentifiers(in: preflightValidator) == [])
        #expect(try credentialIdentifiers(in: remoteAnchor) == [])
        #expect(try credentialIdentifiers(in: stageValidator) == [])
        #expect(
            try credentialIdentifiers(in: releaseLookup) == [
                "GH_TOKEN",
                "github.token",
            ]
        )
        #expect(
            try credentialIdentifiers(in: policyCheck) == [
                "GH_TOKEN",
                "RELEASE_ADMIN_TOKEN",
                "secrets.RELEASE_ADMIN_TOKEN",
            ]
        )
        #expect(
            try credentialIdentifiers(in: stageJob) == [
                "GH_TOKEN",
                "RELEASE_ADMIN_TOKEN",
                "github.token",
                "secrets.RELEASE_ADMIN_TOKEN",
            ]
        )
        #expect(try credentialIdentifiers(in: exactTagJob) == [])
        #expect(
            try credentialIdentifiers(in: publishJob) == [
                "GH_TOKEN",
                "github.token",
            ]
        )
        #expect(releaseLookup.contains("repos/$GITHUB_REPOSITORY/releases/tags/$VERSION"))
        #expect(policyCheck.contains("RELEASE_ADMIN_TOKEN: ${{ secrets.RELEASE_ADMIN_TOKEN }}"))
        #expect(policyCheck.contains("X-GitHub-Api-Version: $API_VERSION"))
        #expect(policyCheck.contains("repos/$GITHUB_REPOSITORY/immutable-releases"))
        #expect(policyCheck.contains(".enabled == true"))
    }

    @Test("Candidate code and explicit release credentials use separate jobs")
    func candidateExecutionAndCredentialsAreJobIsolated() throws {
        let workflow = try workflow
        let preflightJob = try section(
            in: workflow,
            from: "  preflight:",
            to: "  recovery-state:"
        )
        let recoveryStateJob = try section(
            in: workflow,
            from: "  recovery-state:",
            to: "  release-gate:"
        )
        let releaseGateJob = try section(
            in: workflow,
            from: "  release-gate:",
            to: "  release-compatibility:"
        )
        let compatibilityJob = try section(
            in: workflow,
            from: "  release-compatibility:",
            to: "  exact-revision-consumer:"
        )
        let revisionConsumerJob = try section(
            in: workflow,
            from: "  exact-revision-consumer:",
            to: "  stage-release:"
        )
        let stageJob = try section(
            in: workflow,
            from: "  stage-release:",
            to: "  exact-tag-consumer:"
        )
        let exactTagJob = try section(
            in: workflow,
            from: "  exact-tag-consumer:",
            to: "  publish-release:"
        )
        let publishJob = workflow[try #require(
            workflow.range(of: "  publish-release:")
        ).lowerBound...]
        let stableSemVerPattern = #"STABLE_SEMVER_PATTERN='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'"#
        let fullSHAPattern = #"FULL_SHA_PATTERN='^[0-9a-f]{40}$'"#

        #expect(preflightJob.contains("Tools/validate-release-candidate.sh"))
        #expect(releaseGateJob.contains("Tools/validate-release-candidate.sh"))
        #expect(releaseGateJob.contains("swift test"))
        #expect(try credentialIdentifiers(in: preflightJob) == [])
        #expect(try credentialIdentifiers(in: releaseGateJob) == [])
        #expect(try credentialIdentifiers(in: compatibilityJob) == [])
        #expect(try credentialIdentifiers(in: revisionConsumerJob) == [])

        for credentialedJob in [recoveryStateJob, stageJob, publishJob] {
            #expect(!credentialedJob.contains("Tools/"))
            #expect(!credentialedJob.contains("uses: ./"))
            #expect(!credentialedJob.contains("run: swift"))
            #expect(!credentialedJob.contains("\n          swift "))
        }

        #expect(!recoveryStateJob.contains("actions/checkout"))
        #expect(recoveryStateJob.contains(stableSemVerPattern))
        #expect(recoveryStateJob.contains("[[ ! \"$VERSION\" =~ $STABLE_SEMVER_PATTERN ]]"))
        for writeJob in [stageJob, publishJob] {
            #expect(writeJob.contains(stableSemVerPattern))
            #expect(writeJob.contains(fullSHAPattern))
            #expect(writeJob.contains("[[ ! \"$VERSION\" =~ $STABLE_SEMVER_PATTERN ]]"))
            #expect(writeJob.contains("[[ ! \"$EXPECTED_SHA\" =~ $FULL_SHA_PATTERN ]]"))
        }
        #expect(
            try credentialIdentifiers(in: recoveryStateJob) == [
                "GH_TOKEN",
                "github.token",
            ]
        )
        #expect(
            try credentialIdentifiers(in: stageJob) == [
                "GH_TOKEN",
                "RELEASE_ADMIN_TOKEN",
                "github.token",
                "secrets.RELEASE_ADMIN_TOKEN",
            ]
        )
        #expect(try credentialIdentifiers(in: exactTagJob) == [])
        #expect(
            try credentialIdentifiers(in: publishJob) == [
                "GH_TOKEN",
                "github.token",
            ]
        )
        #expect(releaseGateJob.contains("needs: recovery-state"))
        #expect(compatibilityJob.contains("needs: recovery-state"))
        #expect(revisionConsumerJob.contains("needs: recovery-state"))
        #expect(stageJob.contains("      - recovery-state"))
        #expect(stageJob.contains("      - release-compatibility"))
        #expect(stageJob.contains("      - exact-revision-consumer"))
        #expect(exactTagJob.contains("needs: stage-release"))
        #expect(publishJob.contains("      - stage-release"))
        #expect(publishJob.contains("      - exact-tag-consumer"))
    }

    @Test("Release publication includes legacy toolchain compatibility")
    func legacyToolchainCompatibilityIsRequired() throws {
        let workflow = try workflow
        let compatibilityJob = try section(
            in: workflow,
            from: "  release-compatibility:",
            to: "  exact-revision-consumer:"
        )

        #expect(compatibilityJob.contains("scenario: swift-6.2"))
        #expect(compatibilityJob.contains("xcode: \"26.2\""))
        #expect(compatibilityJob.contains("scenario: xcode-26.5"))
        #expect(compatibilityJob.contains("xcode: \"26.5\""))
        #expect(compatibilityJob.contains("ref: ${{ inputs.commit_sha }}"))
        #expect(compatibilityJob.contains("--filter StrictConcurrencyBuildTests"))
        #expect(compatibilityJob.contains("--filter ExternalConsumerContractTests"))
    }

    @Test("Release publication requires a remote exact-revision consumer")
    func exactRevisionConsumerIsRequired() throws {
        let workflow = try workflow
        let consumerJob = try section(
            in: workflow,
            from: "  exact-revision-consumer:",
            to: "  stage-release:"
        )

        #expect(consumerJob.contains("ref: ${{ inputs.commit_sha }}"))
        #expect(consumerJob.contains("Tests/RemoteConsumerSmoke"))
        #expect(consumerJob.contains("{{INNODI_REVISION}}"))
        #expect(consumerJob.contains("INNODI_REVISION: ${{ inputs.commit_sha }}"))
        #expect(consumerJob.contains("swift package --package-path \"$INNODI_REMOTE_CONSUMER\" resolve"))
        #expect(consumerJob.contains("swift run --package-path \"$INNODI_REMOTE_CONSUMER\" --skip-build MacroOnlyApp"))
        #expect(consumerJob.contains("swift run --package-path \"$INNODI_REMOTE_CONSUMER\" --skip-build ValidatedApp"))
    }

    @Test("Immutable publication waits for an exact-version consumer")
    func exactTagConsumerPrecedesPublication() throws {
        let workflow = try workflow
        let stageJob = try section(
            in: workflow,
            from: "  stage-release:",
            to: "  exact-tag-consumer:"
        )
        let tagConsumerJob = try section(
            in: workflow,
            from: "  exact-tag-consumer:",
            to: "  publish-release:"
        )
        let publishJob = workflow[try #require(
            workflow.range(of: "  publish-release:")
        ).lowerBound...]

        #expect(stageJob.contains("git -C \"$REPOSITORY_DIR\" tag -a \"$VERSION\" \"$EXPECTED_SHA\""))
        #expect(stageJob.contains("verify_release_payload true false true"))
        #expect(tagConsumerJob.contains("exact: \\\"$INNODI_VERSION\\\""))
        #expect(tagConsumerJob.contains("state.get(\"version\")"))
        #expect(tagConsumerJob.contains("state.get(\"revision\")"))
        #expect(tagConsumerJob.contains("swift build --package-path \"$INNODI_TAG_CONSUMER\" -c release"))
        #expect(publishJob.contains("--field draft=false"))
    }

    @Test("Tag publication requires monotonic main ancestry")
    func monotonicMainAnnotatedTagCreation() throws {
        let workflow = try workflow

        #expect(
            workflow.contains(
                "git -C \"$REPOSITORY_DIR\" tag -a \"$VERSION\" \"$EXPECTED_SHA\""
            )
        )
        #expect(workflow.contains("cat-file -p \"refs/tags/$VERSION\""))
        #expect(workflow.contains("LOCAL_TAG_TARGET_SHA"))
        #expect(workflow.contains("LOCAL_TAG_TARGET_TYPE"))
        #expect(workflow.contains("LOCAL_EMBEDDED_TAG_NAME"))
        #expect(workflow.contains("REMOTE_TAG_TARGET_SHA"))
        #expect(workflow.contains("REMOTE_TAG_TARGET_TYPE"))
        #expect(workflow.contains("REMOTE_EMBEDDED_TAG_NAME"))
        #expect(workflow.contains("[[ \"$LOCAL_TAG_TARGET_SHA\" != \"$EXPECTED_SHA\""))
        #expect(workflow.contains("|| \"$LOCAL_TAG_TARGET_TYPE\" != \"commit\""))
        #expect(workflow.contains("|| \"$LOCAL_EMBEDDED_TAG_NAME\" != \"$VERSION\""))
        #expect(workflow.contains("[[ \"$REMOTE_TAG_TARGET_SHA\" != \"$EXPECTED_SHA\""))
        #expect(workflow.contains("|| \"$REMOTE_TAG_TARGET_TYPE\" != \"commit\""))
        #expect(workflow.contains("|| \"$REMOTE_EMBEDDED_TAG_NAME\" != \"$VERSION\""))
        #expect(workflow.contains("git -C \"$REPOSITORY_DIR\" push --porcelain"))
        #expect(!workflow.contains("push --atomic"))
        #expect(!workflow.contains("--force-with-lease"))
        #expect(!workflow.contains("\"${EXPECTED_SHA}:refs/heads/main\""))
        #expect(workflow.contains("\"refs/tags/$VERSION:refs/tags/$VERSION\""))
        #expect(!workflow.contains("LOCAL_TAG_NAME"))
        #expect(!workflow.contains("+refs/tags/"))
        #expect(!workflow.contains("--force refs/tags/"))
        #expect(workflow.components(separatedBy: "merge-base --is-ancestor").count - 1 == 2)
        #expect(
            workflow.components(
                separatedBy: "verify_expected_is_remote_main_ancestor"
            ).count - 1 == 3
        )
        #expect(!workflow.contains("TAG_PREEXISTED"))
    }

    @Test("Write-token job never executes candidate-owned code")
    func publishJobIsolatesCandidateCheckout() throws {
        let workflow = try workflow
        let stageJob = try section(
            in: workflow,
            from: "  stage-release:",
            to: "  exact-tag-consumer:"
        )
        let unscopedGitPattern = try NSRegularExpression(
            pattern: #"(?m)^\s+git (?!-C \"\$REPOSITORY_DIR\")"#
        )
        let candidateExecutablePattern = try NSRegularExpression(
            pattern: #"(?m)^\s+(?:\./)?release-repository/"#
        )
        let publishSource = String(stageJob)
        let range = NSRange(publishSource.startIndex..., in: publishSource)

        #expect(stageJob.contains("path: release-repository"))
        #expect(stageJob.contains("path: release-assets"))
        #expect(stageJob.contains("REPOSITORY_DIR: release-repository"))
        #expect(!stageJob.contains("Tools/"))
        #expect(!stageJob.contains("swift"))
        #expect(!stageJob.contains("uses: ./"))
        #expect(!stageJob.contains("release-repository/"))
        #expect(!stageJob.contains("gh release verify"))
        for line in stageJob.split(separator: "\n")
        where line.contains("$REPOSITORY_DIR") {
            #expect(line.contains("git -C \"$REPOSITORY_DIR\""))
        }
        #expect(unscopedGitPattern.firstMatch(in: publishSource, range: range) == nil)
        #expect(candidateExecutablePattern.firstMatch(in: publishSource, range: range) == nil)
    }

    @Test("Release policy requires an exact immutable tag ruleset")
    func immutableTagPolicyIsFailClosed() throws {
        let workflow = try workflow
        let policyCheck = try section(
            in: workflow,
            from: "      - name: Require immutable release and tag policies",
            to: "      - name: Stage annotated tag and draft release"
        )

        #expect(policyCheck.contains("RELEASE_TAG_RULESET_ID: ${{ vars.RELEASE_TAG_RULESET_ID }}"))
        #expect(policyCheck.contains("rulesets/$RELEASE_TAG_RULESET_ID"))
        #expect(policyCheck.contains(".target == \"tag\""))
        #expect(policyCheck.contains(".enforcement == \"active\""))
        #expect(policyCheck.contains(".bypass_actors | type == \"array\" and length == 0"))
        #expect(policyCheck.contains(".conditions.ref_name.exclude | type == \"array\" and length == 0"))
        #expect(policyCheck.contains(". == \"~ALL\""))
        #expect(policyCheck.contains(". == (\"refs/tags/\" + $version)"))
        #expect(policyCheck.contains(". == \"refs/tags/*\""))
        #expect(policyCheck.contains("index(\"update\") != null"))
        #expect(policyCheck.contains("index(\"deletion\") != null"))
        #expect(policyCheck.contains("index(\"creation\") == null"))
    }

    @Test("Release policy requires monotonic main history")
    func monotonicMainPolicyIsFailClosed() throws {
        let workflow = try workflow
        let policyCheck = try section(
            in: workflow,
            from: "      - name: Require immutable release and tag policies",
            to: "      - name: Stage annotated tag and draft release"
        )

        #expect(
            policyCheck.contains(
                "RELEASE_MAIN_RULESET_ID: ${{ vars.RELEASE_MAIN_RULESET_ID }}"
            )
        )
        #expect(policyCheck.contains("rulesets/$RELEASE_MAIN_RULESET_ID"))
        #expect(
            policyCheck.contains(
                "--argjson rulesetID \"$RELEASE_MAIN_RULESET_ID\""
            )
        )
        #expect(policyCheck.contains(".target == \"branch\""))
        #expect(policyCheck.contains(".enforcement == \"active\""))
        #expect(
            policyCheck.contains(
                ".bypass_actors | type == \"array\" and length == 0"
            )
        )
        #expect(
            policyCheck.contains(
                ".conditions.ref_name.exclude | type == \"array\" and length == 0"
            )
        )
        #expect(policyCheck.contains(". == \"refs/heads/main\""))
        #expect(policyCheck.contains(". == \"refs/heads/*\""))
        #expect(policyCheck.contains("index(\"non_fast_forward\") != null"))
        #expect(policyCheck.contains("index(\"deletion\") != null"))
        #expect(policyCheck.contains("index(\"update\") == null"))
        #expect(policyCheck.contains("index(\"creation\") == null"))
    }

    @Test("Release environment requires reviewed main-only deployment")
    func protectedReleaseEnvironmentIsFailClosed() throws {
        let workflow = try workflow
        let policyCheck = try section(
            in: workflow,
            from: "      - name: Require immutable release and tag policies",
            to: "      - name: Stage annotated tag and draft release"
        )

        #expect(workflow.contains("    environment: release"))
        #expect(policyCheck.contains("repos/$GITHUB_REPOSITORY/environments/release"))
        #expect(policyCheck.contains("$environment.name == \"release\""))
        #expect(policyCheck.contains("$environment.can_admins_bypass == false"))
        #expect(policyCheck.contains("select(.type == \"required_reviewers\")"))
        #expect(policyCheck.contains("$requiredReviewerRules | length == 1"))
        #expect(
            policyCheck.contains(
                "$requiredReviewerRules[0].prevent_self_review == true"
            )
        )
        #expect(policyCheck.contains("type == \"array\" and length >= 2"))
        #expect(
            policyCheck.contains(
                "[$requiredReviewerRules[0].reviewers[].reviewer.login]"
            )
        )
        #expect(policyCheck.contains("unique | length >= 2"))
        #expect(policyCheck.contains("protected_branches: false"))
        #expect(policyCheck.contains("custom_branch_policies: true"))
        #expect(
            policyCheck.contains(
                "environments/release/deployment-branch-policies?per_page=100"
            )
        )
        #expect(policyCheck.contains(".total_count == 1"))
        #expect(policyCheck.contains(".branch_policies[0].name == \"main\""))
        #expect(!policyCheck.contains(".branch_policies[0].type"))
    }

    @Test("Published assets must match deterministic same-run artifacts")
    func publishedAssetsUseExactLocalDigests() throws {
        let workflow = try workflow

        #expect(workflow.contains("Tools/package-release-docc.sh"))
        #expect(!workflow.contains("tar -C .build/docc -czf"))
        #expect(!workflow.contains("verify_release_payload false true false"))
        #expect(
            workflow.components(separatedBy: "verify_release_payload false true true").count - 1 == 2
        )
        #expect(workflow.contains("for asset in innodi-docc.tar.gz release-notes.md SHA256SUMS"))
    }

    @Test("Release publication converges through a verified draft")
    func convergentImmutableRelease() throws {
        let workflow = try workflow

        #expect(workflow.contains("repos/$GITHUB_REPOSITORY/releases/tags/$VERSION"))
        #expect(workflow.components(separatedBy: "--paginate --slurp").count - 1 == 2)
        #expect(workflow.contains("select(.tag_name == $version)"))
        #expect(workflow.contains("gh release create \"$VERSION\""))
        #expect(workflow.contains("--draft"))
        #expect(workflow.contains("gh release upload \"$VERSION\""))
        #expect(workflow.contains("--clobber"))
        #expect(workflow.contains("verify_release_payload true false true"))
        #expect(workflow.components(separatedBy: "inspect_remote_tag").count - 1 >= 6)
        #expect(workflow.contains("api --method PATCH"))
        #expect(workflow.contains("repos/$GITHUB_REPOSITORY/releases/$RELEASE_ID"))
        #expect(workflow.contains("--field draft=false"))
        #expect(workflow.contains("verify_release_payload false true true"))
        #expect(workflow.contains("gh release verify \"$VERSION\""))
        #expect(workflow.contains("gh release verify-asset \"$VERSION\""))
        #expect(workflow.contains("sha256sum --check --strict SHA256SUMS"))
    }

    private func section(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> Substring {
        let start = try #require(source.range(of: startMarker)?.lowerBound)
        let end = try #require(
            source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound
        )
        return source[start..<end]
    }

    private func credentialIdentifiers(
        in source: some StringProtocol
    ) throws -> Set<String> {
        let source = String(source)
        let pattern = try NSRegularExpression(
            pattern: #"\b([A-Z][A-Z0-9_]*TOKEN[A-Z0-9_]*)\b|\$\{\{\s*(github\.token|secrets\.[A-Za-z0-9_]+)\s*\}\}"#
        )
        let range = NSRange(source.startIndex..., in: source)
        return try Set(
            pattern.matches(in: source, range: range).map { match in
                for group in 1...2 where match.range(at: group).location != NSNotFound {
                    let range = try #require(Range(match.range(at: group), in: source))
                    return String(source[range])
                }
                Issue.record("Credential expression did not expose a captured identifier")
                return ""
            }
        )
    }
}
