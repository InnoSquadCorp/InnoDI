# Diagnostics Guide

Reference for the diagnostic codes emitted by InnoDI's macros and build-time
validators.

## Overview

Every error, warning, or note the InnoDI macros produce carries a stable code
of the form `InnoDI.<category>.<id>` (for example, `InnoDI.validation.container.dependency-cycle`).
This page groups the codes by category, explains what triggers each one, and
links to the recovery path. Code IDs are intended to be grep-able; message
text may be refined between releases without changing the ID.

The category prefix reflects the stage that emits the diagnostic:

- `InnoDI.usage.*` — structural errors about *how* the macro is attached
  (wrong declaration kind, missing type annotation, conflicting attributes).
- `InnoDI.validation.*` — semantic errors detected by the validator that
  runs after parsing (missing factories, cycles, unknown dependencies,
  hierarchy violations).

## Common recovery patterns

Most diagnostics embed the fix directly in the message. Patterns you'll see
repeatedly:

- **"Use `@Provide(.shared, …)` / `.transient` / `.input`."** — the scope
  argument is wrong for the declared property.
- **"Spell `Lazy<T>` directly."** — a `typealias` was used for a deferred
  wrapper; the macro reads syntax, so aliased forms silently become hard
  edges.
- **"Wrap one factory parameter in `Lazy<T>`."** — a dependency cycle can be
  broken without restructuring by deferring one edge.
- **"Remove the user-defined `Overrides` type."** — the container's nested
  type collides with the synthesized overrides builder.

## Provide-scope diagnostics

Most frequently-hit codes:

- `provide.single-binding` — `@Provide` supports one variable per declaration.
- `provide.named-property-required` — the binding must have a name.
- `provide.explicit-type-required` — the binding must have a type annotation.
- `provide.unknown-scope` — `.shared` / `.transient` / `.input` only.
- `provide.input-invalid-configuration` — `.input` members cannot carry
  factory, type, async factory, or dependency wiring configuration.
- `provide.shared-factory-required` — `.shared` needs `factory:`, `type:`, or
  a property initializer.
- `provide.transient-factory-required` — `.transient` needs `factory:` or
  `type:`.
- `provide.factory-conflict` — `factory:` and `asyncFactory:` both supplied.
- `provide.async-factory-invalid-scope` — `asyncFactory:` is only valid for
  `.shared`.
- `provide.async-factory-must-be-async` — the supplied closure is not `async`.
- `provide.concrete-opt-in-required` — `.shared`/`.transient` with a concrete
  type needs `concrete: true`.
- `provide.unresolved-factory-parameter` — a factory parameter doesn't match
  any container member or `with:` key path.
- `provide.unavailable-dependency-reference` — a factory references a member
  that is declared later and is unavailable at that construction point.
- `provide.unresolved-with-dependency` — a `with:` key path doesn't refer to
  a container member.
- `provide.lazy-unsupported-target` — `Lazy<T>` parameter pointing at a type
  not declared as a container member.
- `provide.provider-non-transient-target` — `Provider<T>` resolved to a
  `.shared` or `.input`; providers require `.transient` targets.
- `provide.provider-unsupported-target` — `Provider<T>` parameter with no
  matching container member.
- `provide.provider-eager-call` — `Provider<T>` invoked at construction
  time, which defeats its purpose.
- `provide.lazy-aliased` / `provide.provider-aliased` — a `typealias` for
  `Lazy<T>` / `Provider<T>` was used; rewrite as the direct spelling.
- `transient-factory.unnamed-parameters` — a transient factory closure used
  shorthand or wildcard parameters; name parameters so InnoDI can inject them.

## Container-level diagnostics

- `container.unknown-dependency` — a referenced name doesn't map to any
  container member.
- `container.dependency-cycle` — hard cycle detected; break with `Lazy<T>`
  or `Provider<T>`, or restructure ownership.
- `container.custom-init-unsupported` — `@DIContainer` already synthesizes
  an initializer; remove the user-written one.
- `container.overrides-name-conflict` — the user's nested `Overrides` type
  collides with the synthesized builder.
- `container.mainactor-conflict` — `@DIContainer(mainActor: true)` combined
  with an asynchronous factory that can't run on the main actor.

## SubContainer diagnostics

- `sub.single-binding`, `sub.named-property-required`,
  `sub.explicit-type-required` — structural rules mirroring `@Provide`.
- `sub.scope-required` — `@SubContainer` requires an explicit
  `scope: .shared` or `.transient`.
- `sub.unknown-scope` — the `scope:` value is not `.shared` or `.transient`.
- `sub.conflicts-with-provide` — a property can't carry both attributes.
- `sub.overrides-name-conflict` — generated child override helper storage
  would collide with an existing parent member name.
- `sub.unknown-parent-member` — `with:` key path doesn't map to a parent
  container member.
- `sub.unknown-child-input` — `bindings:` child key path doesn't map to a
  child input.
- `sub.bindings-conflicts-with-with` — `bindings:` and `with:` reference
  the same child input.
- `sub.duplicate-child-binding` — the same child input is bound twice.
- `sub.shared-parent-must-not-be-transient` — `.shared` sub-container
  cannot read a `.transient` parent.

## Graph-level diagnostics (build plugin)

- `graph.dependency-cycle` — global DAG (across `@DIComponent` graph)
  detected a cycle.
- `graph.ambiguous-container-reference` — a name matched multiple
  containers.

## SwiftUI diagnostics

- `swiftui.feature-root-without-subcontainer` — `@DIFeatureRoot` must
  accompany a `@SubContainer` property.
- `swiftui.feature-root-duplicate-default` — two `@DIFeatureRoot` defaults
  on the same container.
- `swiftui.feature-root-helper-name-conflict` — generated helper name
  collides with an existing member.
- `swiftui.feature-root-invalid-alias` — the feature-root alias argument
  cannot be parsed as a valid Swift identifier.
- `swiftui.environment-bridge-unknown-member` — `@DIEnvironmentBridge`
  key path doesn't resolve to a container member.
- `swiftui.environment-bridge-duplicate-member` — the same key path is
  listed twice.
- `swiftui.environment-bridge-invalid-keypath` — the argument isn't a
  key-path literal.
- `swiftui.environment-bridge-invalid-arguments` — the bridge macro received
  arguments outside its supported key-path list shape.

## Component / Hierarchy diagnostics

- `component.requires-container` — `@DIComponent` must be attached to a
  `@DIContainer`-marked type.
- `component.overrides-builder-required` — `@DIComponent` requires the
  synthesized overrides builder.
- `hierarchy-root.requires-container` — `@DIHierarchyRoot` must be
  attached to a `@DIContainer` type.

## Internal diagnostics

- `internal.codegen-invariant` — the code generator encountered a case
  validation should have rejected. The message embeds the internal
  description; please file a bug with the full diagnostic text.
