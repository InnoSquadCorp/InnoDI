# Validation

InnoDI validates dependency definitions in two layers.

## Local Container Validation

Macro validation checks:

- unknown scopes
- missing required factories
- invalid `.input` factory configuration
- concrete opt-in (`concrete: true`) requirements
- local dependency cycles / unknown dependencies
- async factory validity (`factory` conflict, scope mismatch, non-async closure)

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

## See Also

- <doc:DIContainer>
- <doc:Provide>
