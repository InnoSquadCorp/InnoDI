# Dependabot native auto-merge contract

This repository prepares automatic **squash** merging for verified Dependabot
PRs, including major and SwiftSyntax/toolchain updates. Group boundaries, exact
SwiftSyntax requirements, prebuilt contracts and historical fixtures stay intact.
A partial toolchain update that breaks companion-file or compatibility checks
cannot merge. No additional human approval count is introduced; existing native
review policies continue to apply.

## Standby versus activation

The implementation PR does not change repository settings. The original
preparation baseline had native auto-merge disabled. During the 2026-10-01
Ready-reporting incident, the owner removed only the Ready required-check entry
to merge PR #43; strict **CI Required** and the other protections remained.
The reporting repair does not restore that entry or activate automation.
The coordinator refuses to arm a bot PR unless all of these conditions are true:

- `DEPENDABOT_AUTO_MERGE_ENABLED` repository Actions variable equals `true`.
- Repository native auto-merge and squash merging are enabled.
- Active repository-native main protection strictly requires **CI Required** and
  **Dependabot Merge Ready**, each pinned to GitHub Actions integration `15368`.
  Strict checks require the branch to be current with main. Owner activation
  verifies that the coordinator app has no bypass; it never requests bypass.
- The current immutable bot identity, PR metadata and full CI evidence pass.

No direct merge API or `gh pr merge --auto` fallback is permitted. Native
`enablePullRequestAutoMerge(expectedHeadOid)` arms a request while the Ready
check is pending. The check becomes successful only after a third metadata/CI
read agrees with the first two. Native strict required checks own the actual
merge and base freshness after the final API read.

The REST API hides `bypass_actors` from tokens without ruleset write access.
A missing field is not evidence of an empty list. Runtime checks reject any
visible coordinator-app bypass and any visible `current_user_can_bypass` value
other than `never`; the owner verifies the app's no-bypass configuration once
during activation. There is no runtime audit of every administrator, no new
Administration token and no implicit empty-list substitution.

Human PRs receive a successful Ready check meaning **automatic merging is
ineligible**. They still require CI and the existing review/protection policy
for manual merging. The manual job has no contents or PR write permissions,
never enables auto-merge, and also handles draft human PRs. Ready never includes
itself in its proof inputs, so there is no required-check cycle.

## PR-bound Ready reporting and recovery

A successful Checks API response alone does not prove that GitHub evaluates the
check for the PR's required-check rule. GitHub documents an event eligibility
restriction for checks created by Actions workflow jobs. The reporter therefore
creates Ready **only inside the latest exact-head `pull_request_target` run** of
the trusted coordinator. Its identity includes PR number, head SHA, run ID and
attempt; its details link names that attempt. It first creates an `in_progress`
check, verifies the returned app, SHA, identity and suite, then re-reads current
PR/run metadata before publishing success. The Checks API does not accept a
suite selector, so a different returned suite is rejected rather than assumed
correct. The API checks are necessary provenance checks, not proof of GitHub's
internal required-check evaluation.

`workflow_run`, schedule, push and manual-dispatch reconciliation can update only
an already-issued check bound to that latest PR run/attempt. They cannot create a
replacement in their own suite or reuse a historical successful check. A newer
run/attempt, changed head, failed or cancelled latest source, missing association
or missing issued check fails closed. Existing legacy/historical Ready checks
remain evidence only and are never selected for updates. Superseded PR-target
notifications do not overwrite the newer decision. Bot binding failures still
protectively cancel an outstanding verified bot auto-merge request.

The coordinator's own transport jobs cannot be CI inputs: the running bot job
and waiting post-merge job would wait for themselves. Only exact job/check pairs
from API-verified coordinator PR-target runs are excluded, with workflow ID/path,
repository, event, PR/head, app, suite, job check URL and canonical job details URL
all checked. A name lookalike, foreign app/suite, unassociated check or arbitrary
job is not exempt. Full CI, external checks, bot identity, major/toolchain proof,
review guards and native strict rules are unchanged.

The read-only `post-merge-plan` job prevents unrelated human PR activity from
entering the global post-merge queue. Human PR lifecycle/CI notifications with no
bot targets skip the planner; bot coordination and main/periodic recovery may
run it. It reports `needed=true` only for one authoritatively verified actual bot
merge at current main with no existing exact-main CI. Unmerged/human heads and
already-existing CI are normal non-targets, so the write job is skipped. Missing
or ambiguous metadata and API failures fail the planner and cannot masquerade as
a successful no-op. The write job requires a successful positive plan, re-reads
all authoritative metadata and CI state, and rejects a changed planned PR/SHA
before dispatch. No failure is converted to success and no prior cancelled run
is deleted or relabeled.

PR #48's original main-based post-merge check recorded the annotation
`Canceling since a higher priority waiting request for dependabot-post-merge exists`.
That was a pending-queue replacement before any runner step, not a code failure.
The repair is not used by PR-target runs until it reaches the trusted main
workflow; a passing PR test is not a live observation of this behavior.

Per-PR and post-merge concurrency use `queue: max` with `cancel-in-progress: false`
to prevent ordinary notifications replacing the single pending reporter. GitHub
caps this queue at 100; cancellation, queue overflow and runner failures are
still possible. Missing or ambiguous CI/review notification PR arrays trigger
read-only target enumeration from the live open-main PR API. They do not supply
approval evidence; each bot still must pass its own exact full-CI proof.

After merging this repair, bootstrap an existing PR through a fresh PR lifecycle
event, or rerun its latest PR-target issuer using the updated trusted script.
Rerunning only post-merge advances the run attempt without issuing a new Ready;
rerun all jobs (or the actual Ready issuer) to recover. Manual dispatch and the
hourly schedule cannot bootstrap a missing PR-bound check. Manual fork PRs whose
Actions run omits its PR association also fail closed; do not treat an older
success as recovery or re-enable a globally required Ready rule until that path
has been validated for the repository's supported PR sources.

Before the owner restores Ready as required, verify on a real PR that its latest
check is visible in the PR checks section and recognized by GitHub's required
check evaluation. Transcript tests do not establish that platform behavior.
No rule, permission, credential or repository setting is changed by this repair.

Current GitHub documentation supports `queue: max`. Actionlint 1.7.12 does not
parse that newer key (upstream [issue #680](https://github.com/rhysd/actionlint/issues/680));
the repository guards and YAML parsing still apply. Do not globally disable
syntax checking to hide this isolated tool-version limitation.

## Authoritative proof

`Tools/dependabot-merge-policy.py` reads GitHub APIs only. Event payloads are
wake-ups, not approval evidence. Author must be `dependabot[bot]`, user ID
`49699333`, type `Bot`, on an open, non-draft, conflict-free PR with same-repository
head and base `main`. Labels, actor, branch name, title and update size do not
establish identity or eligibility.

The latest exact-head `pull_request` run of the active
`.github/workflows/macro-tests.yml` is re-read by ID and attempt. Its repository,
workflow ID/path, PR association, recorded head/base SHA and current test-merge
parents must agree with current head/main. An older base run, failed rerun,
pending newer run, ambiguous connection or unavailable metadata blocks approval.

All REST jobs/checks/statuses and GraphQL review-thread pages are collected.
InnoDI requires 18 successful jobs, including each reusable example, both
sanitizers, platform loop, both compatibility lanes, clean coverage, the
Xcode 26.6 consumer contracts and the final **CI Required**, plus the
explicitly non-target `append-perf-history` skip. Each job is bound to its
GitHub Actions app, suite, job ID, details URL, head/test-merge SHA and
validation steps. The exact-SHA consumer job must also prove the isolated macro
consumer uses matching prebuilt SwiftSyntax on the primary Xcode 27 lane; a
combined macro/plugin build alone is insufficient. Source fallback, a missing
proof or another toolchain cannot satisfy this step. Missing/duplicate jobs,
wrong apps, foreign ready checks, unassociated current-suite results, failure,
cancellation, neutral, pending and unexpected skips fail closed. Only the
predefined PR Pages upload, published-main-only consumer guard,
post-merge-origin guard and the Swift 6.2 lane's dispatch-only compiler canary
steps may skip. A test derives the check and step names from the CI workflow
and requires this policy and its transcript inventory to match them. Archived
earlier CI runs/attempts are superseded only by the fully validated latest
run/attempt. Other current checks must succeed.

Latest effective reviews must contain no `CHANGES_REQUESTED` or pending review;
a later comment does not clear requested changes. Requested reviewers/teams,
native review decision and unresolved threads also block approval. Review
submitted/edited/dismissed and review-comment changes trigger a zero-permission
notice. Its `workflow_run` wakes the trusted API coordinator; rerun `in_progress`
also invalidates readiness (`requested` is not emitted for reruns). Main pushes,
PR lifecycle/base edits, hourly reconciliation and manual dispatch re-evaluate
current facts. Obsolete run notifications cannot overwrite a newer gate.

GitHub Actions does not support the `pull_request_review_thread` webhook as a
workflow trigger. Thread resolution/unresolution is observed on the next other
wake-up or hourly API reconciliation. No new required approval count is added.
With the existing count-zero review policy, the interval between the last API
read and a newly submitted review/thread change is **not an atomic review
lock**. Ready failure and cancellation occur after the supported event is
processed; this must not be described as a complete server-side review-race
guarantee. Native strict CI is enforced independently. If atomic review locking
is required, it needs a separately approved review-policy decision.

Failed proof invalidates Ready and protectively cancels a verified bot's
outstanding native request. A main-to-other-base edit does the same. Uncertain
mutation outcomes are read back; they never cause blind retries or direct merge.
Turning the flag off prevents new approvals and reconciliation cancels known bot
requests; it is not a synchronous emergency stop. Disable the repository feature
or manually cancel outstanding requests for an immediate stop.

## Trusted execution and token permissions

The coordinator always checks out `refs/heads/main` with credentials not
persisted. Every mutating job also requires the exact default-main workflow
reference and `refs/heads/main` execution ref before starting; the CLI repeats
that context check before any mutation. A branch-selected manual dispatch is
ineligible even if its workflow happens to contain the same checkout setting.
Post-merge `always()` additionally requires a successful inspect job, so an
inspect failure/skip cannot dispatch recovery. It executes only the repository-owned Python standard-library script
and API requests. No PR checkout, dependency install, cache, downloaded artifact
or PR-controlled shell command is used. All actions remain full-SHA pinned.
Default workflow permissions remain `contents: read`; write permissions are
limited to these explicit jobs:

| Job | Permissions | Purpose |
| --- | --- | --- |
| inspect | contents/actions/checks/pull-requests read | Resolve current API targets |
| manual-ready | contents/actions/pull-requests read, checks write | Complete human manual gate without enabling auto-merge |
| bot-ready | contents/pull-requests/checks write, actions read | Managed readiness check and native enable/cancel after proof |
| post-merge-plan | contents/actions/pull-requests read | Verify that actual current-main bot recovery is needed |
| post-merge | contents/pull-requests read, actions write | Revalidate the planned PR/SHA and dispatch fixed CI/main recovery only |
| review notice | none | Constant message; no checkout or secrets |
| CI Plan | contents/pull-requests read | Verify actual merged bot origin when recovery input exists |

These are persistent workflow permissions once this PR is merged, requiring the
owner's activation review. No new PAT, App installation, secret or credential is
created. `actions: write` is a broad GitHub token scope, so the post-merge job
exposes no arbitrary workflow/ref interface: only `macro-tests.yml`, `main` and
the verified actual merged bot PR number are hardcoded in trusted code. The
permission guard rejects changes outside this reviewed map.

## Post-merge main CI and documentation

A merge using `GITHUB_TOKEN` cannot be assumed to trigger ordinary push/closed
workflows. The read-only planner therefore checks for native completion after bot
coordination with at most seven reads spaced five seconds apart. Main/periodic
recovery checks once; independent hourly reconciliation provides recovery even
if completion events are suppressed. It considers only a unique actually merged bot PR
whose merge commit equals **current main**, verifies it twice, and dispatches
only `macro-tests.yml` on `main`. Existing exact-main push or marked recovery CI
runs prevent duplicates, including failed runs; retries require operator review.
Unknown dispatch outcomes are read back, never blindly retried.

The recovery input is not itself authorization. CI Plan checks the immutable bot
identity, same repository, closed/merged state, merge commit, actual current main
and `GITHUB_SHA`. A changed main rejects publication. That successful origin step
alone enables the reusable DocC Pages artifact and post-CI performance history.
Docs accepts only a successful main CI workflow at the fixed path, and still
compares its originating SHA with remote main before deploying. Other manual
CI, PRs and release candidates publish no Pages artifact. The dispatch may fail
closed if main moves during the API/dispatch window; the next main push or
reconciliation covers the new tip. Hourly reconciliation may be delayed by
GitHub scheduling and is not a delivery-time SLA. Actual native merging and this
post-merge path remain untested live until activation; metadata transcript tests
and CI do not substitute for that observation.

## Owner-approved activation order

1. Review this implementation PR's exact-head CI and manually merge the prepared
   code. Do not enable automation on the implementation PR or any human PR.
2. Keep the flag absent/false. Trigger or rerun a trusted PR-target issuer for
   each already-open main PR as described above. Verify latest-run provenance
   and actual PR required-check recognition before making Ready required. A
   coordinator manual dispatch cannot create the initial PR-bound check.
3. Preserve the existing main deletion/non-fast-forward rules and no-bypass
   policy. Add one `required_status_checks` rule to ruleset `15303479` with
   `strict_required_status_checks_policy: true`, and contexts `CI Required` and
   `Dependabot Merge Ready`, both `integration_id: 15368`. Leave existing review
   policy, other protections and credentials unchanged. Audit effective inherited
   and classic rules as well; unavailable APIs are not evidence of no protection.
4. Enable repository `allow_auto_merge: true` (squash already enabled). With the
   flag still off, do not manually arm bot PRs. Inspect existing native requests;
   the initially observed bot PRs 45/46 had none and incomplete/failing CI.
5. Set repository Actions variable `DEPENDABOT_AUTO_MERGE_ENABLED=true` last and
   dispatch the coordinator on main. Confirm failing/pending bot PRs remain
   blocked, successful eligible updates use native auto-merge, and the actual
   merged SHA receives main CI/DocC recovery. Creating missing ecosystem labels
   is a separate approved optional settings step.

Required activation changes: repository feature, strict check rule, repository
variable and the reviewed job token scopes above. They are **prepared, not
applied by this PR**. Native runtime capability, check-reset API behavior,
review-race limitations and post-merge recovery must be observed on real bot
updates before reporting that automatic merging is operational.

References: [Dependabot Actions automation](https://docs.github.com/en/code-security/tutorials/secure-your-dependencies/automate-dependabot-with-actions),
[workflow events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows),
[Checks API suite assignment](https://docs.github.com/en/rest/guides/using-the-rest-api-to-interact-with-checks),
[concurrency queue limits](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency),
[GITHUB_TOKEN recursion limits](https://docs.github.com/en/actions/concepts/security/github_token),
[native auto-merge input](https://docs.github.com/en/graphql/reference/input-objects#enablepullrequestautomergeinput),
[strict required checks](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks).
