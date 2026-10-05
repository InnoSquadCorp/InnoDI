# InnoDI agent skill

The canonical [InnoDI skill](innodi/SKILL.md) lives in this repository. It helps
an AI coding tool implement, test, diagnose, or migrate a consumer using its
actual resolved InnoDI version. The bundled references and consumer target
public **7.0.0**, revision `4783eee7f674f99a337768c107b7a5f640810c2a`;
they do not establish support for every 7.x version or unreleased `main`.

## Ownership and distribution

- Edit `skills/innodi/` here. When a library change affects consumer guidance,
  update the skill and its behavioral fixture in the same PR.
- The shared `innosquad-agent-skills` project assembles versioned snapshots
  for Codex and Claude Code. It owns plugin manifests, catalogs, and host
  installation/selection evaluations. Bundled copies are not independent
  authoring sources.
- A distribution snapshot must record the source repository, skill path,
  exact source commit and content identity. It must separately record the
  supported library release and revision from
  [support.json](innodi/references/support.json).
- Skill documentation fixes can ship independently of library releases.
  Pin the skill's source commit rather than assuming its source must exist
  in the library's release tag. Preserve previously released snapshots.
- Keep every runtime resource inside `skills/innodi/`. A standalone copy must
  not require the library checkout, another InnoSquad skill, or an MCP server.

The shared plugin is currently a review-stage pilot, not a public release.
Automatic collection and publication are follow-up work. The InnoDI skill
itself is covered by the repository's [MIT license](../LICENSE); the complete
notice is also included in the skill for redistribution.

## Standalone installation

Copy the **entire** `skills/innodi` directory from a reviewed commit into your
consumer project's skill directory. Check an existing destination before
replacing it; copying only `SKILL.md` drops required references and examples.

| Tool | Destination relative to the consumer project | Explicit invocation |
| --- | --- | --- |
| Codex | `.agents/skills/innodi/` | `$innodi` |
| Claude Code | `.claude/skills/innodi/` | `/innodi` |

Start a new session after installing. Normal automatic selection is enabled;
explicit invocation also works. For example:

> Use the InnoDI skill to check this project's resolved version, inject an
> APIClient, and replace it with a fake in tests.

Choose one installation route in a given project: installing both this
standalone skill and a plugin containing it can expose duplicate guidance.
Cloning this library or adding it through SwiftPM does not install an AI skill.

Host documentation: [Codex skills](https://developers.openai.com/codex/skills)
and [Claude Code skills](https://code.claude.com/docs/en/skills).

## Validate the bundled consumer

From the repository root on macOS with Python 3 and Xcode 27 / Swift 6.4:

```bash
python3 skills/innodi/scripts/validate_consumer.py --scratch-path /tmp/innodi-skill-validation
```

The standard-library-only helper copies the fixture into an external scratch
directory, resolves the remote exact pins, verifies the active graph and clean
checkout revisions, and runs Swift tests with strict concurrency and warnings
as errors. It retains command logs and `evidence.json` under that directory.
Cold caches require network access. It neither installs a skill nor modifies
the consuming application's dependency graph.

The ten tests cover construction, value/optional overrides, typed prewarm,
owned readiness, retry, reader cancellation, close, and preflight failure.
A SwiftUI boundary is compiled but no device lifecycle is exercised.
The checked-in [consumer evidence](validation/consumer-evidence.json) records
the exact fixture hashes and toolchain. This external release consumer does
not test changes to the library's working-tree implementation.

## AI evaluation boundary

The preceding plugin pilot was installed in Codex and Claude Code on
2026-10-05. Codex passed eight representative cases (six automatic selections,
one explicit invocation, and one unrelated task without selection); six
generated consumers passed 29 Swift tests. Those historical results concern
the plugin installation, not a new evaluation of these standalone paths.
Claude registered the plugin skill but its first AI request failed with
OAuth 401 before using model tokens, so Claude behavior remains unqualified.

The skill instructions, references, script, and consumer were transferred
without behavioral changes; only the redistribution notice was updated to
reflect ownership here. Re-run host evaluations when behavior or discovery
metadata changes. Full repeated bilingual evaluation, 6.x migration execution,
SwiftUI device behavior, and combined-library resolution remain unverified.
