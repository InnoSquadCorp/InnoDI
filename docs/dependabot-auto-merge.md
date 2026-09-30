# Dependabot native auto-merge contract

This repository prepares automatic **squash** merging for verified Dependabot
PRs, including major and SwiftSyntax/toolchain updates. Group boundaries, exact
SwiftSyntax requirements, prebuilt contracts and historical fixtures stay intact.
A partial toolchain update that breaks companion-file or compatibility checks
cannot merge. No additional human approval count is introduced; existing native
review policies continue to apply.

## Standby versus activation

The implementation PR does not change repository settings. At the inspected
baseline, `allow_auto_merge=false` and main ruleset `15303479` contains deletion
and non-fast-forward rules with no bypass actors. The prepared coordinator will
refuse to arm a bot PR unless all of these conditions are true:

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
InnoDI requires 17 successful jobs, including each reusable example, both
sanitizers, platform loop, both compatibility lanes, clean coverage and the
final **CI Required**, plus the explicitly non-target `append-perf-history`
skip. Each job is bound to its GitHub Actions app, suite, job ID, details URL,
head/test-merge SHA and validation steps. The exact-SHA consumer job must also
prove the isolated macro consumer uses matching prebuilt SwiftSyntax on the
primary Xcode 26.6 lane; a combined macro/plugin build alone is insufficient.
Source fallback, a missing proof or another toolchain cannot satisfy this step.
Missing/duplicate jobs, wrong apps,
foreign ready checks, unassociated current-suite results, failure, cancellation,
neutral, pending and unexpected skips fail closed. Only the predefined PR
Pages upload, published-main-only consumer guard and post-merge-origin guard
steps may skip. Archived earlier CI runs/attempts are superseded only by the
fully validated latest run/attempt. Other current checks must succeed.

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
| post-merge | contents/pull-requests read, actions write | Dispatch fixed CI/main recovery only |
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
workflows. The coordinator therefore checks for native completion with a bounded
35-second poll; its independent hourly reconciliation provides recovery even if
those events are suppressed. It considers only a unique actually merged bot PR
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
2. Keep the flag absent/false. Run the trusted coordinator on main to establish
   human Ready check contexts for already-open main PRs; confirm there is no
   pending-check bootstrap cycle before making Ready required.
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
[GITHUB_TOKEN recursion limits](https://docs.github.com/en/actions/concepts/security/github_token),
[native auto-merge input](https://docs.github.com/en/graphql/reference/input-objects#enablepullrequestautomergeinput),
[strict required checks](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks).
