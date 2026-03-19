# Validation

InnoDI validates dependency definitions in two layers.

## Read This Next

Recommended reading path:

1. `README.md` for installation and container syntax
2. this document for local/build/global validation behavior
3. <doc:PolicyBoundaries> for exact matching and exclusion rules
4. <doc:ModuleWideInitDetection> for custom `init` restriction details

## Local Container Validation

Macro validation checks:

- unknown scopes
- missing required factories
- invalid `.input` factory configuration
- strict name-based factory parameter and `with:` resolution
- declaration-order availability for shared dependencies
- concrete opt-in (`concrete: true`) requirements
- local dependency cycles / unknown dependencies
- async factory validity (`factory` conflict, scope mismatch, non-async closure)
- user-defined `init` conflicts inside `@DIContainer` declarations and same-file extensions

Build-stage extension:

- coordinated build validation scans the same package sources for cross-file extension `init` conflicts
- nested path matching is supported, while generic and constrained extensions remain excluded

## Global DAG Validation

Use the graph CLI with build-time validation:

```bash
swift run InnoDI-DependencyGraph --root . --validate-dag
```

Container-level opt-out:

```swift
@DIContainer(validateDAG: false)
```

`validateDAG: false` containers are excluded from DAG cycle and ambiguity checks.

## Build Tool Plugin

Attach `InnoDIDAGValidationPlugin` to a target to fail build on graph validation errors.
The plugin coordinates validation once per normalized AST input state and reuses the shared result across targets.

Observability artifacts:

- shared state lives under the package `.build` directory
- each shared validation signature stores:
  - `result.json`
  - `validation-metrics.json`
  - `validation-summary.md`
- each plugin invocation output stores:
  - `dag-validation-stamp.txt`
  - `dag-validation-metrics.json`
  - `dag-validation-summary.md`
- Markdown summaries include:
  - cache / live-run reason codes
  - file-level change sections for new, deleted, reparsed, and content-hash-reused files
  - top offender style truncated file lists for quick CI inspection
- CI should read artifacts in this order:
  - Markdown summary
  - JSON metrics artifact
  - raw stderr

Verbose logging remains optional through `INNODI_VALIDATION_VERBOSE` or `INNODI_VALIDATION_DEBUG`, but artifact generation is always on.

## Policy Boundaries

For the exact matching and exclusion rules used by macro and build validation, see <doc:PolicyBoundaries>.

## See Also

- <doc:DIContainer>
- <doc:Provide>
- <doc:ModuleWideInitDetection>
- <doc:PolicyBoundaries>
