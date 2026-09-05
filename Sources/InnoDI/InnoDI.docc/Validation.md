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
effect compatibility. It skips global DAG validation, local cycle validation,
and other graph-derived checks only.

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

## See Also

- <doc:DIContainer>
- <doc:Provide>
- <doc:PolicyBoundaries>
- <doc:ModuleWideInitDetection>
