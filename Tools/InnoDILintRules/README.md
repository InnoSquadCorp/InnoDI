# InnoDI SwiftLint Rules

Custom SwiftLint rule fragments that enforce repository-level invariants the
macro plugin cannot diagnose from a single declaration site. Treat them as a
companion gate, not a replacement for the macro's compile-time diagnostics.

## Rules

| Rule | Severity | What it catches |
|---|---|---|
| `innodi_validate_dag_in_production` | error | `@DIContainer(validateDAG: false)` left in the codebase. Pair with the configuration-aware pattern in DAGValidation.md if you need a per-build switch. |
| `innodi_no_lazy_typealias` | warning | `typealias Foo = InnoDI.Lazy<...>` (or `Provider<...>`). The macro detects only canonical identifiers, so a cross-file alias silently disables cycle escape. |

## Adopting

1. Copy `swiftlint-innodi.yml` into your repository (or vendor it via a
   submodule / package resource).
2. Either reference it from your `.swiftlint.yml` `included:` list (SwiftLint
   ≥ 0.55) or merge the `custom_rules:` block into your existing
   `.swiftlint.yml`.
3. Run `swiftlint lint` locally and in CI. The error-severity rules will
   fail the lint step on a violation.

## Maintaining

The rules use SwiftLint's regex-based custom-rule API, so they accept simple
patterns rather than AST queries. Two consequences worth knowing:

* The rules will fire inside a multi-line string that happens to include the
  pattern. Use `// swiftlint:disable:next` to suppress on a known-safe line.
* If the macro signature changes (e.g. a new opt-out parameter), update the
  regex in the same PR that lands the macro change so the lint rule keeps up.

## CI Workflow Guard

SwiftLint does not lint workflow YAML files, so CI opt-out checks live outside
this rules file. Run `Tools/check-ci-validation-opt-out.sh` in CI to reject
`INNODI_DISABLE_BUILD_VALIDATION=1` (or truthy equivalents) in GitHub Actions,
GitLab CI, or CircleCI configuration files.

## Related

- [DAGValidation guide](../../Sources/InnoDI/InnoDI.docc/DAGValidation.md)
- [Plugin opt-out guide](../../Sources/InnoDI/InnoDI.docc/PluginOptOut.md)
- [DiagnosticsGuide](../../Sources/InnoDI/InnoDI.docc/DiagnosticsGuide.md)
