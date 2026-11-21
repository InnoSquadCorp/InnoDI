# Module-Wide Init Detection

`@DIContainer` enforces custom `init` restrictions in both macro and build
validation.

## Macro Layer

Macro validation rejects custom `init` declarations in the annotated type body.
The attached macro receives that declaration, but cannot reliably inspect
sibling extensions in the source file.

## Required Build Layer

Attach `InnoDIDAGValidationPlugin` to every target that declares containers.
Its full-source preflight rejects custom `init` declarations in matching
same-file and cross-file extensions, including declarations inside `#if`
branches, before semantic validation and DAG validation run.

Without the build-validation plugin, the extension-wide custom `init`
prohibition is not guaranteed.

The build layer matches:

- `@DIContainer` declarations by normalized nominal path
- extension `init` declarations by normalized extended type path

The plugin's snapshot holds the target being built and every target it depends
on, and the match stays inside one target: an extension `init` counts only
against a container declared in the extension's own target. A type in another
target that shares a container's name keeps its extension initializers. An
initializer that another module adds to a container must delegate through
`self.init(...)` or `self = ...`, which reaches the synthesized initializer.

## Boundaries

- nested paths are supported
- generic argument extensions are excluded
- constrained `where` extensions are excluded
- unsupported or ambiguous cases remain outside the deterministic rule

Structured failures from this stage are emitted through the same validation
artifact pipeline described in <doc:Validation>.
