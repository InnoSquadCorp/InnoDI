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
- missing factories
- declaration-order availability
- local dependency cycles
- strict name-based resolution
- invalid user-defined `init` declarations
- async factory validity

`validateDAG: false` does not disable structural validation. It only skips the
macro's local cycle and closure/`with:` graph-derived checks.

## Build Validation

The coordinated build pipeline adds:

1. cross-file custom `init` validation
2. semantic container reference checks
3. hierarchy validation for `@DIComponent` and `@DIHierarchyRoot`
4. DAG validation
5. metrics and summary artifact emission

## Global DAG Validation

Use the CLI for global graph validation:

```bash
swift run InnoDI-DependencyGraph --root . --validate-dag
```

`validateDAG: false` containers are excluded from global DAG validation, but
raw-expression `factory:` and initializer references still diagnose at compile
time.

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
