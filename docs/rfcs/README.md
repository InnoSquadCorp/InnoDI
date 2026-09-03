# InnoDI RFCs

This directory holds Request-for-Comments documents for substantial
additions or breaking changes to InnoDI. RFCs are a lighter-weight
alternative to a full design doc review cycle: they capture the
problem, the proposed API, the alternatives considered, and the open
questions in one place so the maintainers can align on direction
before a PR lands.

## Index

| ID   | Title                                 | Status |
|------|---------------------------------------|--------|
| 0001 | [Macro-driven mock generation](0001-macro-mock-generation.md) | Accepted (experimental) |
| 0002 | [SubContainer wiring simplification](0002-subcontainer-wiring-simplification.md) | Implemented |
| 0003 | [Scoped TaskLocal overrides](0003-scoped-task-local-overrides.md) | Draft |
| 0004 | [API surface simplification](0004-api-surface-simplification.md) | Draft (partially superseded) |
| 0005 | [5.0 contract hardening](0005-5.0-contract-hardening.md) | Accepted |
| 0006 | [Assisted subgraphs and container roles](0006-assisted-subgraphs-and-container-roles.md) | Draft |

## Conventions

- One markdown file per RFC, numbered `NNNN-kebab-case-title.md`.
- Status progresses: `Draft` → `Accepted` → `Implemented` (or `Rejected`).
- `Deferred` means an accepted direction is paused on an upstream blocker;
  it can return to `Draft` when that blocker is resolved.
- Accepted RFCs do not need to be rewritten once implementation lands —
  but include a link from the release notes to the RFC for context.
- Breaking-change RFCs must include a migration section before they can
  move past `Draft`.
