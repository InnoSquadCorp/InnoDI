# Policy Boundaries

InnoDI keeps validation deterministic by choosing a few explicit boundaries.

## Custom `init` Detection

- Macro validation rejects custom `init` declarations in the annotated type.
- Macro validation also rejects same-file extensions whose type path matches the
  annotated type.
- Build validation extends the same rule to cross-file extensions.

## Matching Strategy

- `InnoDIMacros`, `InnoDICore`, and the graph CLI share the same lightweight
  nominal-path model where possible.
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

## Concrete Opt-In

- Protocol-first dependency design is preferred.
- Concrete `.shared` and `.transient` storage requires explicit
  `concrete: true`.

## See Also

- <doc:Validation>
- <doc:ModuleWideInitDetection>
