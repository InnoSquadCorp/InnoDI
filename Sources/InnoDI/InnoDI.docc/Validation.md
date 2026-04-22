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

Construction invariants such as factory requirements and scope restrictions are
always enforced. The only per-container validation opt-out is `validateDAG: false`,
which disables global DAG validation plus the macro's local cycle and
closure/`with:` graph-derived diagnostics while leaving structural invariants in
place. Raw-expression `factory:` / initializer references still diagnose at
compile time.

## Build Validation Pipeline

Coordinated build validation runs in this order:

1. signature collection across package Swift sources
2. cross-file custom `init` validation
3. semantic validation for container references and deferred wrapper spelling
4. workspace hierarchy validation for `@DIHierarchyRoot` / `@DIComponent`
5. DAG validation
6. metrics / summary artifact emission

The coordinator now waits for shared-run lock turnover through an async backoff
loop. Lock recovery, timeout behavior, reason codes, and emitted artifact names
stay the same; only the coordinator's internal wait path changed.

Build-stage extensions:

- coordinated build validation scans the same package sources for cross-file extension `init` conflicts
- semantic validation adds structured checks for module-local container references and deferred wrapper spelling rules
- hierarchy validation enforces rooted ownership across modules when at least one `@DIHierarchyRoot` exists
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
The macro also skips local cycle plus closure/`with:` graph-derived diagnostics
for those containers, but raw-expression `factory:` / initializer references
still diagnose at compile time. Structural rules such as factory requirements,
scope restrictions, and semantic build validation still apply.

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

## Implementation Map

Read these source files in this order if you are maintaining build validation:

1. `ValidationSignature.swift` for source discovery, manifest caching, and stable signature generation
2. `ContainerSemanticBuildValidator.swift` for module-wide semantic diagnostics before DAG validation
3. `WorkspaceHierarchyBuildValidator.swift` for rooted cross-module component validation
4. `DependencyResolution.swift` for declaration-order availability rules shared by graph collection and macro fix-it filtering

## Policy Boundaries

For the exact matching and exclusion rules used by macro and build validation, see <doc:PolicyBoundaries>.

## See Also

- <doc:DIContainer>
- <doc:Provide>
- <doc:ModuleWideInitDetection>
- <doc:PolicyBoundaries>
