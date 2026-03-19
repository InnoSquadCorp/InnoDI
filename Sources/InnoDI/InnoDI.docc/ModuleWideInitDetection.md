# Module-Wide Init Detection

`@DIContainer` now enforces custom `init` restrictions in two layers.

Read this after <doc:Validation> and <doc:PolicyBoundaries>. This page is intentionally narrower than the main validation guide.

## Macro Layer

Macro validation rejects custom `init` declarations in:

- the annotated type body
- same-file extensions whose type path exactly matches the annotated type

This keeps macro diagnostics fast and local to the expansion context.

## Build Layer

The build plugin extends the same rule to cross-file extensions.

During coordinated build validation, InnoDI scans the package sources and matches:

- `@DIContainer` declarations by normalized nominal path
- extension `init` declarations by normalized extended type path

Cross-file matches fail the build with the same `container.custom-init-unsupported` rule used by macro diagnostics.

## Current Matching Rules

Build validation keeps the same safety boundary as macro validation while allowing a small semantic helper pass before falling back to source text:

- nested paths like `Outer.Container` are supported
- semantic helper resolution may match a unique alias or qualified suffix before fallback
- generic argument extensions are excluded
- constrained `where` extensions are excluded
- ambiguous cases fall back to the existing conservative source-text rule

This keeps the build-stage rule deterministic while improving accuracy for straightforward cross-file matches.
