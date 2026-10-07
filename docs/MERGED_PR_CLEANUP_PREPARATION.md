# Merged-PR cleanup: executable local preparation

`.github/workflows/merged-pr-cleanup.yml` and `merged_pr_cleanup.py` are executable, reviewed local changes. Automatic merged-PR cancellation is enabled by default in the proposed workflow; no standalone cancellation API calls were performed.

The trusted `pull_request_target: closed` workflow requires a merged PR in this exact repository. It checks out the immutable trusted workflow SHA, never PR code, and loads only the reviewed executor, selector and allowlist. Unset/empty or `INNO_MERGED_PR_CLEANUP=enabled` runs the separately authorized job with `actions: write`. Explicit `disabled` or unrecognized values run read-only inspection with `actions: read`. Both have `pull-requests: read` and `contents: read`, with no code-writing permission.

The executor verifies repository identity, default-branch workflow context and checkout SHA. It freshly fetches the merged PR and complete bounded paginated run inventory before writes. It selects only unfinished `pull_request` runs in the PR lifetime, with a sole native association to this repository and PR and an exact matching association/run head. Previous heads of this same PR are included. Missing associations or ambiguous identity fail closed. A rerun explicitly started after merge is preserved when its attempt/start-time evidence establishes that fact.

Main push, merge_group, manual/workflow_run events, release/publication/docs-publish, protected stateful workflows, other PRs, completed runs, and same-SHA other events remain excluded. The repository-specific `ci-cleanup-workflows.json` is an exact trusted allowlist.

Immediately before each cancellation the executor re-fetches the PR and run/attempt. Changed or completed candidates are skipped. A 409 is reconciled against fresh completed status; 403 is not retried. HTTP redirects are forbidden and response sizes are bounded. The only write endpoint is the selected run's `/cancel` endpoint.

GitHub's cancel API is run-ID based, not attempt-conditional. A rerun can begin between the final GET and POST; the API provides no atomic exclusion. Thus protection against simultaneous reruns is best-effort, not an absolute guarantee. This limit is exercised by mocked race tests and must be accepted during rollout review.

The user explicitly approved this scoped actions-write permission on 2026-10-07. Read-only API inspection found no repository override. Before merge, validate the workflow/allowlist with a disposable non-release PR and real native API associations; an explicit disabled override is available for inspection. Local mocked pagination, provenance, attempts, fork, forbidden-event, permission and race tests are not hosted cancellation evidence. No token is persisted in the prepared artifacts.
