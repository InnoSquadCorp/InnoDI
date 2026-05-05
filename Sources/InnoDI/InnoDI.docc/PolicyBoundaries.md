# Policy Boundaries

InnoDI keeps validation deterministic by choosing a few explicit boundaries.

## Custom `init` Detection

- Macro validation rejects custom `init` declarations in the annotated type.
- Macro validation also rejects same-file extensions whose type path matches the
  annotated type.
- Build validation extends the same rule to cross-file extensions.

## Matching Strategy

- `InnoDIMacros`, `InnoDICore`, and `InnoDI-DependencyGraph` share and
  guarantee the same lightweight nominal-path model and aligned parser/graph
  semantics.
- Nested paths such as `Outer.Container` are supported.
- Generic argument extensions and constrained `where` extensions are excluded.
- Unsupported or ambiguous cases stay outside the semantic rule instead of
  producing speculative matches.

## Declaration Order

- `.input` members are always available.
- sync `.shared` members can reference inputs and earlier sync shared members.
- async `.shared` members can reference inputs, sync shared members, and
  earlier async shared members.
- `.transient` members may reference any container member, but names still
  resolve strictly.

## Isolation and Sendability

- Containers keep their generated storage inside the container value. InnoDI
  does not install dependencies into a global registry.
- `mainActor: true` applies `@MainActor` to generated container APIs and is the
  preferred shape for UI-root containers.
- `Lazy<T>` and `Provider<T>` wrappers are not a cross-actor transport
  mechanism. Treat them as staying inside the container's isolation domain
  unless `T` and the surrounding call path are already safe to move.
- Non-`Sendable` dependencies should be passed through explicit container
  boundaries and isolated by the app layer, not hidden behind global lookup.

## DAG Opt-Outs

- `validateDAG: false` disables graph-derived cycle and unresolved-reference
  checks for that container.
- Structural validation still runs. Unsupported custom `init` declarations,
  invalid `@SubContainer` bindings, malformed deferred wrappers, and other
  local macro rules are still diagnosed.
- Use the opt-out only for deliberate integration boundaries such as legacy
  modules, temporary migration steps, or containers whose real lifetime is
  validated by another system.

## Deferred Wrapper Limits

- `Lazy<T>` and `Provider<T>` defer container-member access after init-time
  wiring, so those edges are rendered but excluded from hard cycle detection.
- The deferral is only effective when the factory receives and stores/calls the
  wrapper itself. If a factory immediately calls the wrapper while constructing
  the dependency, the dependency is effectively eager again.
- Indirect eager calls through helper functions are not type-checked by InnoDI;
  review those factories manually when breaking cycles with deferred wrappers.

## Concrete Opt-In

- Protocol-first dependency design is preferred.
- Concrete `.shared` and `.transient` storage requires explicit
  `concrete: true`.

## Runtime Lookup Tradeoffs

- InnoDI intentionally has no `@Injected` property wrapper.
- InnoDI intentionally has no dynamic registration API.
- Use runtime DI tools when late registration or plugin-style composition is
  the primary need. Use InnoDI when generated initializers, explicit overrides,
  and deterministic validation are the primary need.

## See Also

- <doc:Validation>
- <doc:IntegrationGuide>
- <doc:ModuleWideInitDetection>
