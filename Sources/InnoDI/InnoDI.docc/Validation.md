# Validation

InnoDI validates dependency definitions in layers.

## Read This Next

Recommended reading order:

1. `README.md`
2. this document
3. <doc:PolicyBoundaries>
4. <doc:ModuleWideInitDetection>

## Macro Validation

Macro validation checks:

- scope rules
- direct, plain, stored instance-`var` placement for `@Provide`
- missing factories
- declaration-order availability
- local dependency cycles
- strict name-based resolution
- effect compatibility on explicit sibling edges
- invalid user-defined `init` declarations
- async factory validity

The explicit sibling-edge sources are named parameters on the root
`factory:`/`asyncFactory:` closure literal and literal `with:` key paths paired
with `Type.self`. Non-closure factories and property initializers are opaque
zero-edge sources and must not reference sibling members.

`validateDAG: false` does not disable declaration validation or explicit-edge
effect compatibility. It skips global DAG validation and local graph-derived
availability checks. Local ownership cycles are always rejected, including
cycles through `Lazy` or `Provider`.

## Build Validation

The coordinated build pipeline adds:

1. cross-file custom `init` validation
2. semantic container reference checks
3. hierarchy validation for component and root `@DIContainerRole` declarations
4. DAG validation
5. metrics and summary artifact emission

## Global DAG Validation

Use the CLI for global graph validation:

```bash
swift run InnoDI-DependencyGraph --root . --validate-dag
```

`validateDAG: false` containers are excluded from global DAG validation, but
unsupported provider declarations and effect mismatches on explicit sibling
edges still diagnose at compile time.

## Artifacts

Build validation emits:

- `validation-metrics.json`
- `validation-summary.md`
- `dag-validation-metrics.json`
- `dag-validation-summary.md`

These artifacts are part of the documented release contract in `RELEASING.md`.
They remain in the plugin work directory and its validation-state directories;
the plugin does not declare reports as target resources. Swift targets declare
only a comment-only generated Swift file to order validation before compilation.
Clang targets use output-free commands so no Swift source is introduced. Xcode
project targets retain output-free gates to avoid collisions between build
destinations. SwiftPM consumers require tools version 6.0 or later for
output-free commands.

The plugin forwards only the documented coordinator environment controls:
`INNODI_LOCK_TIMEOUT`, `INNODI_STALE_LOCK_AGE`, `INNODI_ALLOW_UNSAFE_LOCK`,
`INNODI_VALIDATION_VERBOSE` and `INNODI_VALIDATION_DEBUG`. Set them in the
environment that launches the build. The coordinator still validates their
values and retains its existing defaults, including refusing unsafe
filesystems unless the operator explicitly opts in. See <doc:lock-safety>.

## See Also

- <doc:DIContainer>
- <doc:Provide>
- <doc:PolicyBoundaries>
- <doc:ModuleWideInitDetection>
