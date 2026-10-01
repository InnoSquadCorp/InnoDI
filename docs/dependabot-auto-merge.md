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
- An active, verifiable repository-native `pull_request` rule requires resolved
  review threads. A configured approving-review count of zero remains allowed;
  this code does not add or change an approval count.
- The required-check and PR/thread rulesets expose `current_user_can_bypass=never`
  for the actual coordinator job token. Missing/redacted capability evidence is
  standby, not assumed safe.
- The current immutable bot identity, PR metadata and full CI evidence pass.

No direct merge API or `gh pr merge --auto` fallback is permitted. Native
`enablePullRequestAutoMerge(expectedHeadOid)` arms a request only after the
latest native Ready reporter succeeded and three fresh exact metadata/CI proofs
and reporter-binding reads agree. All reads precede arming because GitHub can
merge immediately when Ready is already successful; they are not a post-merge
rollback guard. Failed fresh proof protectively cancels any still-outstanding
verified bot request. Ready is a snapshot, not an attestation of a
newer CI/base tuple: the coordinator always independently re-proves that current
tuple before arming. Native strict required checks own actual merging and base
freshness after the final read.

The REST API hides `bypass_actors` from tokens without ruleset write access.
A missing field is not evidence of an empty list. Runtime checks reject any
visible coordinator-app bypass and require a runtime `current_user_can_bypass`
value of `never` from the actual job token for both status and review/thread
rules. A previous owner audit is not a substitute for missing current evidence. There is no runtime audit of every administrator, no new
Administration token and no implicit empty-list substitution.

Human PRs receive a successful native Ready job meaning **automatic merging is
ineligible**. They still require CI and whatever native review/protection policy
the owner configured for manual merging. The reporter is read-only, never enables
auto-merge, and also handles draft human PRs. A verified native reporter job is
excluded from its own proof inputs, preventing a required-check cycle.

At the 2026-10-01 follow-up read, ruleset `15303479` required only strict
**CI Required** from app `15368`, plus deletion/non-fast-forward protection.
It contained neither Ready nor a pull-request/review/thread-resolution rule.
The owner-visible read also showed an OrganizationAdmin bypass and
`current_user_can_bypass=always` for that reader. This is owner-controlled
operating state, not a change made by this PR or proof that the Actions app can
bypass. It is not silently restored or treated as an empty bypass list.
Native auto-merge and squash were enabled. This is **not active bot approval**:
`native_rules` rejects missing Ready or a verifiable native PR/thread-resolution
barrier, and the feature flag must also allow approval. The coordinator does not
assume either review protection or runtime no-bypass evidence exists. Effective inherited/classic protections must be inspected separately;
an unavailable API is not evidence that they are absent. No live setting changes
are part of this follow-up.

## Native Ready reporting and bounded refresh

The live PR #49 observation disproved the API-created-check approach: latest
PR-target run `36821543991` expected suite `99729364696`, but the created Ready
check `110238127816` landed in older suite `99729103311`, and GitHub replaced its
requested attempt URL. The provenance guard correctly refused success. The
follow-up removes every Checks API POST/PATCH instead of weakening that guard.

`.github/workflows/dependabot-ready.yml` is a dedicated, short Ubuntu
`pull_request_target` reporter with one job named exactly **Dependabot Merge
Ready**. There is no job-level condition or matrix that could publish a skipped
required job. Guards execute inside its read-only steps. It checks out the
immutable `github.workflow_sha`, never PR code. That trusted workflow source SHA
is distinct from the Actions API run's PR `head_sha`.

The evaluation step produces an explicit boolean only after successful API and
provenance reads. A separate enforce step exits nonzero for an ineligible bot,
standby, or missing/failed/pending full proof. API, checkout and unexpected errors
fail evaluation; they cannot become a successful native job merely because the
background `coordinate` command returns a human-readable blocked message.
GitHub Actions alone owns the native check's status and final conclusion.

Fork runs can omit REST `pull_requests` associations. The trusted reporter
therefore records a versioned event binding in both its run name and its native
evaluation-step name: PR number, head SHA, head/base repository IDs, base branch
and immutable workflow source. These values come from GitHub's PR-target event,
not a PR title, body, branch-name guess or an uploaded artifact. The resolver
checks current PR metadata, the fixed workflow/event/repositories, trusted source
ancestry and the native job/check/app/suite against that binding. A run title
alone is insufficient. Present REST associations must still match exactly and
cannot be overridden by this fallback. Foreign or incomplete metadata blocks.

The executing snapshot also rechecks its original event head/base/repositories
against the current PR. Latest verdicts and refresh writers require the exact
current policy definition. Historical check attribution verifies its original
event/job binding and trusted source ancestry without treating an old policy as
a current verdict. This avoids retaining a permanent failure merely because a
new reporter definition was deployed on the same PR head. A fresh lifecycle is
still required to create a latest reporter from the current trusted definition.
The fork path requires a hosted canary before restoring Ready as required; local
transcript tests do not establish live fork association or required-check UI behavior.

The main-based coordinator plans a refresh only when the latest exact-PR/head
reporter is terminal with a controlled evaluated verdict and current eligibility
differs. Running/queued reporters and unchanged failure/success spend no reruns.
The narrowly scoped `ready-refresh` job can rerun only that verified reporter job,
never CI or another workflow. It rechecks PR/head, workflow ID/path/event,
run/attempt, sole job, app, suite, check URL and canonical job details before the
request. An already-armed bot must be protectively cancelled by `bot-ready`
before this writer runs; the writer independently refuses a still-armed bot.
Reporter completion is a metadata wake-up for the coordinator, which still
requires fresh full proof before any native auto-merge request.

Reruns retain their original workflow definition. The resolver verifies trusted
source ancestry and compares the exact blob IDs of both workflow definitions and both
runtime policy scripts against current main. An incompatible old definition
requires a fresh PR lifecycle event rather than repeatedly rerunning old code.
Cancelled, missing, ambiguous, neutral/skipped or infrastructure-failed reporters
also require operator recovery. The implementation stops before 30 days and at
50 total attempts; it does not spend retries on unchanged blocked eligibility.

Every refresh target is a bounded `{PR, head, run, attempt, job}` tuple. Its
Actions writer-job name records the PR/run/attempt. Per-PR concurrency serializes
writers. Authenticated writer-job history since reporter creation is a conservative
observed-history interlock: an earlier started/failed/uncertain request prevents a
second automatic POST for the same source attempt. The writer verifies its own running claim/start time and rejects incomplete
or contradictory history. Queued claims are ignored only when their runs were
created after this writer started; earlier or terminal-run/queued records block.
This is not a claim of atomic exactly-once API consistency and requires the live
uncertain-response canary below.
Ordinary simultaneous CI/notice/schedule wakes can pre-plan contenders before
the first writer starts. Ambiguous queued history deliberately stops both rather
than assuming no earlier request executed; this can require operator recovery
even when no POST occurred. That availability tradeoff is tested and must be
included in the live canary, not advertised as a perfectly automatic retry loop. After one POST, including a lost response,
it only reads back attempt advancement. If acceptance stays uncertain, inspect
it or explicitly rerun the native reporter to obtain a new attempt; do not rerun
the refresh writer blindly. There are no new comments, cache claims, tokens or
status-check writes used as a journal.

Only exact API-verified coordinator transport and native reporter job/check
pairs are excluded from full CI proof. An arbitrary Ready-name check, wrong app,
suite, job URL or missing native job is never exempt. Historical native attempts
are attributed by their real Actions jobs; they never replace the latest verdict.
GitHub may expose the exact unevaluated matrix-name expression for a PR-target
`ready-refresh` job that never expands. This transport is recognized only with
terminal `skipped` job/check results and an empty step list, exact
workflow/event/run/attempt/head/app/suite/URL binding, and a successful native
`inspect` job carrying its immutable trusted source SHA. The inspector checks
out `github.workflow_sha`; old source attribution must remain main ancestry.
Names with different text, executed steps, missing source or other outcomes
remain blocked. Legacy same-head coordinator runs without that source marker
can require an explicitly approved fresh commit; a new metadata event alone
cannot establish the missing historical source.
Legacy API-created same-name checks are not adopted. Existing affected PR heads
may need an explicitly approved fresh commit/lifecycle after deployment, and
require a deliberate migration check before restoring the required rule.

The read-only `post-merge-plan` guard remains unchanged: unrelated human activity
skips recovery, and the writer needs a successful positive plan for one actual
bot merge at current main with no existing exact-main CI. It revalidates the
planned PR/SHA before fixed main dispatch. No old cancelled/failing run is deleted
or relabeled as success.

Coordinator writer queues retain `queue: max`, `cancel-in-progress: false`.
The dedicated native reporter cancels superseded per-PR runs. Queue/runner
failures remain possible and never authorize adopting an older successful run.
Actionlint 1.7.12 does not parse the newer queue key ([upstream #680](https://github.com/rhysd/actionlint/issues/680));
all other lint and repository guards remain enabled.

### Trusted deployment and live validation boundary

Changing this PR does not change the `pull_request_target` definition on main.
Before a separate owner-approved merge, only local/PR CI tests can exercise the
new logic. Do not execute unmerged PR code with a write token or weaken the
trusted-main guard to obtain a green demonstration.

After deployment, keep automatic approval disabled and use a fresh non-auto-merge
canary PR/lifecycle. Verify the sole native fixed-name check, exact head, latest
run/attempt/suite and actual PR required-check recognition. Observe a bounded
reporter-only rerun, its completion wake-up and cancellation behavior; an API
request acknowledgment is not final readiness. Test legacy same-name migration
and supported fork associations explicitly. Rerunning the old API-based workflow
cannot load the new reporter definition. Missing reporter sources cannot be
bootstrapped by schedule/manual reconciliation.

Only after those observations may the owner separately restore Ready as required
or activate bot merging. No required-rule, repository setting, new credential,
merge or release is performed by this PR. The proposed job-scope change was
explicitly approved: `ready-refresh` gains Actions write while old Checks write
permissions are removed. Actual reporter/required-check and native auto-merge
operation remain unverified until trusted-main deployment and live validation.

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
sanitizers, platform loop, both compatibility lanes, clean coverage, the
Xcode 26.6 consumer contracts and the final **CI Required**, plus the
explicitly non-target `append-perf-history` and exhaustive-redundant
`Fast PR contracts` skips. Each job is bound to its
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
A zero approval count remains allowed only with a verified native PR/resolved-thread
barrier. Extra API-only review conditions and the interval between the final read
and arming are still **not an atomic review lock**. Ready failure and cancellation occur after the supported event is
processed; this must not be described as a complete server-side review-race
guarantee. Native strict CI is enforced independently. If atomic review locking
is required, it needs a separately approved review-policy decision.

Failed current proof protectively cancels a verified bot's outstanding native
request. If a completed reporter's verdict is stale, the bounded refresh path
requests a new native verdict; it does not directly overwrite a check. A
main-to-other-base edit remains ineligible and also cancels the request. Uncertain
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
| native reporter `ready` | contents/actions/checks/pull-requests read | Compute/enforce read-only native Ready snapshot |
| ready-plan | contents/actions/checks/pull-requests read | Plan only changed eligible reporter verdicts |
| ready-refresh | contents/checks/pull-requests read, actions write | One verified latest exact-PR/head reporter-job rerun |
| bot-ready | contents/pull-requests write, actions/checks read | Native enable/cancel only after fresh proof and native Ready |
| post-merge-plan | contents/actions/pull-requests read | Verify that actual current-main bot recovery is needed |
| post-merge | contents/pull-requests read, actions write | Revalidate the planned PR/SHA and dispatch fixed CI/main recovery only |
| review notice | none | Constant message; no checkout or secrets |
| CI Plan | contents/pull-requests read | Verify actual merged bot origin when recovery input exists |

These are persistent workflow permissions once this PR is merged, requiring the
owner's activation review. No new PAT, App installation, secret or credential is
created. `actions: write` is a broad GitHub token scope, so the post-merge job
exposes no arbitrary workflow/ref interface: only `macro-tests.yml`, `main` and
the verified actual merged bot PR number are hardcoded in trusted code. The
permission guard rejects changes outside this reviewed map. The new
`ready-refresh` writer exposes only the fixed dedicated reporter path and a
revalidated job ID; its token cannot change contents, checks or PR state.

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
2. Keep the flag absent/false. Trigger a fresh native reporter lifecycle using
   its deployed trusted-main definition, starting with a non-auto-merge canary.
   Verify the native check and one reporter-only rerun round trip as above,
   including existing-head migration and actual required-check recognition.
   Neither a coordinator dispatch nor rerunning the obsolete issuer bootstraps
   the new reporter definition.
3. Preserve the existing main deletion/non-fast-forward rules and no-bypass
   policy. Add one `required_status_checks` rule to ruleset `15303479` with
   `strict_required_status_checks_policy: true`, and contexts `CI Required` and
   `Dependabot Merge Ready`, both `integration_id: 15368`. Leave existing review
   count policy and credentials unchanged. The runtime also requires a verified
   native PR/resolved-thread rule and no-bypass capability; their absence remains
   standby until the owner separately approves any needed policy change. This
   implementation does not add those live rules. Audit effective inherited
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
applied by this PR**. Native runtime capability, reporter-only rerun behavior,
review-race limitations and post-merge recovery must be observed on real bot
updates before reporting that automatic merging is operational.

References: [Dependabot Actions automation](https://docs.github.com/en/code-security/tutorials/secure-your-dependencies/automate-dependabot-with-actions),
[workflow events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows),
[reporter job rerun API](https://docs.github.com/en/rest/actions/workflow-runs#re-run-a-job-from-a-workflow-run),
[rerun source/privileges and limits](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs),
[concurrency queue limits](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency),
[GITHUB_TOKEN recursion limits](https://docs.github.com/en/actions/concepts/security/github_token),
[native auto-merge input](https://docs.github.com/en/graphql/reference/input-objects#enablepullrequestautomergeinput),
[strict required checks](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks).
