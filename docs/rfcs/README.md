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
| 0001 | [Macro-driven mock generation](0001-macro-mock-generation.md) | Draft |
| 0002 | [SubContainer wiring simplification](0002-subcontainer-wiring-simplification.md) | Deferred |

## Conventions

- One markdown file per RFC, numbered `NNNN-kebab-case-title.md`.
- Status progresses: `Draft` → `Accepted` → `Implemented` (or `Rejected`).
- Accepted RFCs do not need to be rewritten once implementation lands —
  but include a link from the release notes to the RFC for context.
- Breaking-change RFCs must include a migration section before they can
  move past `Draft`.
