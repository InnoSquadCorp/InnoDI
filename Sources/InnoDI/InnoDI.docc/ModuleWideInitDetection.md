# Module-Wide Init Detection

`@DIContainer` enforces custom `init` restrictions in both macro and build
validation.

## Macro Layer

Macro validation rejects custom `init` declarations in:

- the annotated type body
- same-file extensions whose type path matches the annotated type

## Build Layer

Build validation extends the same rule to cross-file extensions before semantic
validation and DAG validation run.

The build layer matches:

- `@DIContainer` declarations by normalized nominal path
- extension `init` declarations by normalized extended type path

## Boundaries

- nested paths are supported
- generic argument extensions are excluded
- constrained `where` extensions are excluded
- unsupported or ambiguous cases remain outside the deterministic rule

Structured failures from this stage are emitted through the same validation
artifact pipeline described in <doc:Validation>.
