# Migration and diagnosis

Work from the consumer's resolved source and preserve the requested scope. A migration request authorizes relevant edits; a diagnosis request alone calls for read-only inspection and a concrete proposed change.

## 6.x to 7.0

| Change | Handling |
|---|---|
| Named parent key paths | Migrator rewrites supported forms to `\Self.member`; nested parent paths require manual correction |
| Explicit SwiftUI import | Migrator adds matching imports where ownership/access is unambiguous |
| `try prewarm(\Container.service)` | Manually convert to typed, nonthrowing `prewarm(.service)`; remove obsolete error handling only when no remaining operation throws |
| Host observation and macOS minimum | Manually move host-owner observation to Observation and raise macOS targets to 14 |
| Hosted feature root | Explicitly select `FeatureRoot(..., hosted: true)` if ownership is intended |
| Owned async preparation | Optional architecture choice; not an automatic source rewrite |
| Type/typealias named `Swift` visible to slot-bearing containers | Rename/move the shadow or container based on actual diagnostics; the migrator does not fix it |

From an exact-version InnoDI source checkout that contains the tool, run:

```bash
swift run InnoDI-Migrate --root /path/to/consumer --check
```

Use `--write` when source migration is within the user's request; inspect the diff and rebuild afterward. `swift run` may build the executable even for a read-only check. Repository `Tools/` helpers are not installed as consumer products; do not assume a globally installed command or invent a helper path in the consumer.

`migrate.unqualified-ownership-ambiguous` requires checking which module owns the attribute. Qualify it as `@InnoDI.SubContainer` where appropriate, or trust a module only after checking that it does not declare conflicting macros. Do not trust every import to silence diagnostics. `migrate.legacy-form-unsupported` and `migrate.rewrite-target-ambiguous` need targeted manual changes. For SwiftUI import access ambiguity, narrow the root to the affected target, choose actual `internal`/`package`/`public` requirements, and rebuild with its normal warning/import settings. A successful rewrite is not compile proof.

## Investigation order

1. Capture the actual diagnostic and target. Confirm resolved revision, plugin attachment, deployment floor, compiler, and macro dependency graph.
2. Check the declared provider/child shape and actor boundary against the exact release source. For generated-code errors, reduce the consumer declaration before assuming a runtime bug.
3. Use the shipped `InnoDI-Doctor` when useful; inspect its `--help` for target inputs. Its default diagnosis is read-only and JSON output uses schema v3. Do not add apply/write options for an inspection-only request.
4. Graph consumers in 7.0 use JSON schema v6. The executable is `InnoDI-DependencyGraph`; its `--diff before.json after.json --check-contract` mode reports contract drift with exit status 5. Outdated schemas need migration. Confirm required arguments with that version's help instead of treating every nonzero exit as a build failure.
5. Reproduce the suspected problem in the affected consumer with a passing control; then validate the requested fix under the real target settings. Do not disable validation, rewrite transitive pins, or suppress concurrency errors to get a green result.

Sources: exact [migration guide](https://github.com/InnoSquadCorp/InnoDI/blob/4783eee7f674f99a337768c107b7a5f640810c2a/Sources/InnoDI/InnoDI.docc/MigrationGuide.md), [README tool usage](https://github.com/InnoSquadCorp/InnoDI/blob/4783eee7f674f99a337768c107b7a5f640810c2a/README.md), and [diagnostics guide](https://github.com/InnoSquadCorp/InnoDI/blob/4783eee7f674f99a337768c107b7a5f640810c2a/Sources/InnoDI/InnoDI.docc/DiagnosticsGuide.md).
