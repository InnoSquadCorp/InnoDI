# Policy Boundaries

InnoDI keeps validation deterministic by making a few explicit boundary choices.

Read this after <doc:Validation>. If you need the cross-file custom `init` story in depth, continue to <doc:ModuleWideInitDetection>.

## Custom `init` Detection

- Macro validation rejects custom `init` declarations in the annotated type body.
- Macro validation also rejects same-file extensions whose type path matches the annotated type.
- Build validation extends the same rule to cross-file extensions.

## Matching Strategy

- The semantic validator and the graph CLI share the same lightweight resolver
  model from `InnoDICore`, so container-reference diagnostics and graph
  collection follow the same nominal-path rules.
- Build validation first tries semantic helper resolution for cross-file extension targets.
- The graph CLI and build-stage validators now share the same semantic helper model for nominal paths, nested paths, and collected typealiases.
- If semantic resolution is still ambiguous or unsupported, InnoDI falls back to the existing conservative source-text match where that is explicitly supported.
- Nested paths such as `Outer.Container` are supported.
- DAG reporting uses semantic states directly:
  - `resolved`
  - `ambiguous`
  - `excluded`
  - `unresolved`

## Excluded Extension Shapes

- Generic argument extensions are excluded.
- Constrained `where` extensions are excluded.
- Unsupported or ambiguous extension targets stay outside the build-stage rule instead of producing speculative matches.

## Declaration Order

- `.input` members are always available.
- sync `.shared` members can only reference inputs and earlier sync shared members.
- async `.shared` members can reference inputs, all sync shared members, and earlier async shared members.
- `.transient` members may reference any container member, but names still resolve strictly.

The macro validator uses these same declaration-order rules when deciding
whether a rename or key-path fix-it is safe to suggest. The source of truth for
that availability matrix is `DependencyResolutionContext` in
`Sources/InnoDIMacros/DependencyResolution.swift`.

## Concrete Opt-In

- Protocol-first dependency types are preferred.
- Concrete shared or transient dependency types require explicit `concrete: true`.

## See Also

- <doc:Validation>
- <doc:ModuleWideInitDetection>
