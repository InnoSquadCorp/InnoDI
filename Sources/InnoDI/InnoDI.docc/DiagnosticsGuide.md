# Diagnostics Guide

Reference for the diagnostic codes emitted by InnoDI's macros and build-time
validators.

## Overview

Every error, warning, or note the InnoDI macros produce carries a stable code
of the form `InnoDI.<category>.<id>` (for example, `InnoDI.validation.container.dependency-cycle`).
This page groups the codes by category, explains what triggers each one, and
links to the recovery path. Code IDs are intended to be grep-able; message
text may be refined between releases without changing the ID.

## Assisted factory diagnostics

- `assisted-factory.invalid-declaration`: `@AssistedFactory` must annotate an
  empty, non-generic nested struct named `AssistedFactory`.
- `assisted-factory.missing-declaration`: an assisted input exists without the
  source-visible nested factory bridge.
- `assisted-factory.invalid-arguments`: the child type or literal static and
  assisted key-path lists are missing or malformed.
- `assisted-factory.duplicate-input`: an input appears more than once across
  the static and assisted lists.
- `assisted-factory.input-partition-mismatch`: the factory lists omit,
  misclassify, or add an input compared with the child declaration.

## Multibinding diagnostics

- `multibinding.invalid-contributors`: the argument is not one literal array
  of canonical `\Self.member` key paths.
- `multibinding.empty-contributors`: the contributor list is empty.
- `multibinding.duplicate-contributor`: a contributor appears more than once.
- `multibinding.collection-type-required`: the annotated member does not use
  an array type.
- `multibinding.unknown-contributor`: a key path does not name a direct managed
  dependency on the same container.
- `multibinding.async-contributor`: a synchronous collection references an
  asynchronous provider.
- `multibinding.type-mismatch`: a contributor's written type differs from the
  collection element type.

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
- **"Use named parameters on the root factory closure."** — sibling DI edges
  are not inferred from non-closure expressions, property initializers, nested
  closures, or arbitrary identifiers.

## Provide-scope diagnostics

Most frequently-hit codes:

- `provide.single-binding` — `@Provide` supports one variable per declaration.
- `provide.duplicate-attribute` — a property carries more than one `@Provide`.
  Keep exactly one provider attribute; InnoDI suppresses peer storage and
  accessor generation for the ambiguous declaration.
- `provide.escaped-identifier-unsupported` — a direct provider property or a
  root factory dependency parameter uses a backtick-escaped identifier. Rename
  it to an unescaped identifier. InnoDI 5.0 derives storage and lookup identities
  only from unescaped spellings and fails closed before peer generation.
- `provide.named-property-required` — the binding must have a name.
- `provide.explicit-type-required` — the binding must have a type annotation.
- `provide.opaque-type-unsupported` — the explicit property type uses
  `some Protocol`. Generated storage and overrides need a stable type; expose
  the existential as `any Protocol` instead.
- `provide.iuo-type-unsupported` — the explicit property type is an implicitly
  unwrapped optional `T!`. Replace it with explicit `T` or `T?` so storage and
  sibling wiring have one optionality contract.
- `provide.unknown-scope` — `.shared` / `.transient` / `.input` only.
- `provide.input-invalid-configuration` — `.input` members cannot carry
  factory, type, async factory, or dependency wiring configuration.
- `provide.escaping-invalid-scope` — `escaping: true` was used outside
  `.input`. Remove it from `.shared` / `.transient`; escaping input storage is
  the only supported use.
- `provide.escaping-nonfunction-type` — `@Provide(.input, escaping: true)` was
  applied to an obvious nonfunction or optional-function type shape. Use it
  only for a non-optional function type hidden behind an alias. Identifier and
  member types are accepted conservatively because macros cannot resolve
  aliases; Swift may add its own diagnostic if such an alias does not actually
  resolve to a non-optional function type.
- `provide.shared-factory-required` — `.shared` needs `factory:`, `type:`, or
  a property initializer.
- `provide.transient-factory-required` — `.transient` needs `factory:`,
  `asyncFactory:`, `Type.self`, or a property initializer.
- `provide.factory-conflict` — `factory:` and `asyncFactory:` both supplied.
- `provide.construction-source-conflict` — more than one of `factory:`,
  `asyncFactory:`, `Type.self`, and a property initializer was supplied. Keep
  exactly one construction source.
- `provide.with-requires-type-construction` — `with:` was combined with a
  factory or property initializer. `with:` belongs only to `Type.self` wiring;
  factory closures declare edges with named parameters.
- `provide.async-factory-invalid-scope` — `asyncFactory:` is valid for
  `.shared` and `.transient`, but not `.input`.
- `provide.async-factory-must-be-async` — the supplied closure is not `async`.
- `provide.factory-must-be-sync` — `factory:` was given an `async` closure;
  move async construction to `asyncFactory:`.
- `provide.factory-must-not-throw` — `factory:` was given a throwing closure;
  handle errors inside the factory or move asynchronous throwing work to
  `asyncFactory:`.
- `provide.bool-literal-required` — the `@Provide` Boolean option `escaping:`
  must be literal `true` or `false`.
- `provide.invalid-with-dependencies` — `with:` is not a literal array made
  only of canonical direct-member key paths spelled exactly `\Self.member`, or
  `[]`. Named container, module-qualified, and typealias roots are rejected,
  as are nested components, optional chaining, subscripts, runtime arrays, and
  computed elements.
- `provide.requires-direct-container-member` — `@Provide` was attached outside
  a direct, plain, stored instance `var` in a supported `@DIContainer` struct,
  or used an unsupported accessor/storage modifier. Move the dependency into
  that container and remove `let`, computed/observer accessor blocks, `lazy`,
  `weak`, `unowned`, `static`/`class`, setter-access modifiers, property
  wrappers, and conditional/unknown attributes. Besides `@Provide` itself, no
  source-written property-level attribute is supported. This prohibition
  includes `@MainActor`; request isolation with
  `@DIContainer(mainActor: true)`. Isolation attributes InnoDI generates on
  provider declarations and accessors are internal compiler support.
- `provide.conditional-declaration-unsupported` — the complete `@Provide`
  declaration appears inside `#if`. Move the declaration outside conditional
  compilation and branch inside its factory or injected implementation; this
  prevents peer and accessor macro phases from generating a partial provider.
- `provide.generated-accessor-manual-attachment` — InnoDI's internal provider
  accessor macro (`_InnoDIProvideAccessor`) was attached manually. Remove it
  and use `@Provide` on a direct container member; accessors are compiler-owned.
  A deliberately forged combination with another property wrapper may also
  trigger Swift's own structural diagnostics; those compiler diagnostics are
  expected in addition to this stable InnoDI code.
- `provide.duplicate-factory-parameter` — the root factory closure declares
  the same effective parameter name more than once, including across ordinary,
  `Lazy<T>`, and `Provider<T>` parameters. Give every dependency parameter a
  unique name. InnoDI rejects the provider before constructing its dependency
  lookup tables or generating peer storage.
- `provide.unresolved-factory-parameter` — a named parameter on the root
  factory closure doesn't match any container member or `with:` key path.
- `provide.unavailable-dependency-reference` — a factory references a member
  that is declared later and is unavailable at that construction point.
- `provide.async-dependency-requires-async-consumer` — a synchronous factory
  consumes an async provider through an explicit sibling edge. Move the
  consumer to `asyncFactory:`. This check also runs with `validateDAG: false`.
- `provide.throwing-dependency-requires-throwing-consumer` — a nonthrowing
  factory consumes an `async throws` provider. Make the consumer's
  `asyncFactory:` closure `async throws`. This check also runs with
  `validateDAG: false`.
- `provide.with-dependency-requires-synchronous-provider` — `Type.self` plus
  `with:` targets an async or async-throwing provider. Swift key paths require
  synchronous properties; rewrite the consumer as `asyncFactory:` with a named
  closure parameter.
- `provide.unresolved-with-dependency` — a `with:` key path doesn't refer to
  a container member.
- `provide.lazy-unsupported-target` — `Lazy<T>` points at a member produced by
  `asyncFactory:`; lazy resolvers are synchronous.
- `provide.lazy-eager-call` — `Lazy<T>` invoked during `.shared`
  construction, which turns the soft edge back into an eager edge.
- `provide.provider-non-transient-target` — `Provider<T>` resolved to a
  `.shared` or `.input`; providers require `.transient` targets.
- `provide.provider-unsupported-target` — `Provider<T>` points at an async
  transient member; provider handles are synchronous.
- `provide.provider-eager-call` — `Provider<T>` invoked at construction
  time, which defeats its purpose.
- `provide.lazy-aliased` / `provide.provider-aliased` — a `typealias` for
  `Lazy<T>` / `Provider<T>` was used; rewrite as the direct spelling.
- `transient-factory.unnamed-parameters` — a transient factory closure used
  shorthand or wildcard parameters; name parameters so InnoDI can inject them.

## Container-level diagnostics

- `container.unsupported-declaration-kind` — `@DIContainer` is attached to a
  class, actor, enum, protocol, extension, or another non-struct declaration.
  Move the boundary to a non-generic struct and inject runtime state through
  `.input` members.
- `container.private-access-unsupported` — the container is explicitly
  `private`, so sibling containers cannot access its generated mount surface.
  Use `fileprivate` for file-local mounting, or nest a default-access container
  inside a private namespace.
- `container.generic-unsupported` — the container declares generic parameters
  or is nested in an enclosing generic nominal declaration. Move type-specific
  behavior behind an injected dependency.
- `container.unverifiable-enclosing-context` — the container is declared inside
  an extension, where a syntax-only macro cannot prove whether the extended
  type is generic. Move the declaration to file scope or a non-generic nominal.
- `container.local-declaration-unsupported` — the container is declared in an
  executable scope such as a function, closure, initializer, accessor, switch
  case, or local block. Move it to file scope or a non-generic nominal
  declaration. Swift can also emit its own language diagnostic for inherently
  invalid placements such as a type nested in a generic function or a local
  container stacked with an attached-extension macro such as `@DIComponent`.
  Current Swift toolchains omit accessor ancestry from the attached-macro
  context for a type inside a computed-property body; the build-validation
  plugin and graph CLI full-source preflight emit this diagnostic for that
  shape. Without full-source preflight, Swift or stacked companion macros can
  emit additional diagnostics for an accessor-local component.
- `container.unknown-dependency` — a referenced name doesn't map to any
  container member.
- `container.dependency-cycle` — hard cycle detected; break with `Lazy<T>`
  or `Provider<T>`, or restructure ownership.
- `container.custom-init-unsupported` — `@DIContainer` already synthesizes
  an initializer; remove the user-written one. An initializer in the annotated
  body is diagnosed by the macro. Initializers in same-file or cross-file
  extensions are owned by the required `InnoDIDAGValidationPlugin` full-source
  pass because compiler-plugin macro input does not contain sibling extensions.
- `container.unmanaged-stored-property` — a stored instance member has neither
  `@Provide` nor `@SubContainer`. InnoDI 5.0 owns the complete container
  initializer, including for empty containers; annotate the member or make it
  computed/static.
- `container.overrides-name-conflict` — the user's nested `Overrides` type
  collides with the required synthesized builder. InnoDI 5.0 treats this as
  an error; rename the custom declaration. A diagnostic-only recovery
  initializer prevents mounted child containers from producing unrelated
  Swift argument errors.
- `container.mainactor-conflict` — `@DIContainer(mainActor: true)` is combined
  with another global actor on the container or a dependency member. Remove
  the custom actor or disable `mainActor` generation.
- `container.mainactor-nonisolated-member` — a `@Provide` or `@SubContainer`
  member opts out with `nonisolated`, which contradicts the container's
  `mainActor: true` contract.
- `container.bool-literal-required` — `root:`, `validateDAG:`, or `mainActor:`
  was not literal `true` or `false`; use conditional compilation to choose
  different attribute spellings.
- `container.duplicate-member-name` — two direct managed instance members use
  the same property name, including `@Provide`/`@SubContainer` combinations.
  Rename one property. InnoDI diagnoses the later declaration, notes the
  first, and suppresses support for the ambiguous identity.
- `container.generated-symbol-collision` — distinct managed property names
  map to the same hidden storage, override, or child-builder symbol. Rename
  one `@Provide` or `@SubContainer` property. InnoDI uses source-order
  first-claim-wins diagnostics and puts every managed accessor in recovery so
  no invalid-redeclaration or wrong-storage-type errors cascade from Swift.
- `container.reserved-name-prefix` — a direct container declaration starts
  with one of the prefixes the macro reserves for generated storage and
  support declarations (`_storage_`, `_override_`, `_innoDI`, or `_InnoDI`).
  Rename the declaration. This includes plain variables, functions, nested
  nominal types, typealiases, and declarations inside a top-level `#if`.
- `container.reserved-module-name` — the container, an enclosing nominal, or a
  direct declaration named `InnoDI`, or a direct nested type/typealias named
  `Swift` or `_Concurrency`, shadows a module qualifier used by generated
  support. Rename the declaration. Value members named `Swift` or
  `_Concurrency` remain available. The target-scoped full-source preflight
  extends the same diagnostic to visible declarations in sibling files,
  enclosing members, matching extensions, and imported dependency targets.
- `generated-qualifier.inheritance-unverifiable` — a class that is itself a
  generated site, or lexically encloses one, has a first inherited type that
  the target-scoped source index cannot resolve uniquely. The first inherited
  position can name the superclass, so the validator follows source-visible
  classes and typealiases before generating container or bridge support. A
  known source-visible protocol in that position ends the superclass scan, but
  an SDK-only, binary-only, unresolved, or ambiguous declaration fails closed.
  Move the generated site to a struct/enum or a source-visible adapter, or make
  the inheritance chain available as indexed source. This validator is a
  conservative syntactic index and does not type-check external modules. For a
  class bridge, inherited type members named `Swift` or `SwiftUI` receive the
  corresponding reserved-module diagnostic; inherited `InnoDISwiftUI` is safe,
  although a direct or lexically visible declaration with that name remains
  reserved.

## SubContainer diagnostics

- `sub.single-binding`, `sub.named-property-required`,
  `sub.explicit-type-required` — structural rules mirroring `@Provide`.
- `sub.scope-required` — `@SubContainer` requires an explicit
  `scope: .shared` or `.transient`.
- `sub.escaped-identifier-unsupported` — an `@SubContainer` property uses a
  backtick-escaped identifier. Rename it to an unescaped identifier so child
  storage, override, and SwiftUI helper identities remain canonical.
- `sub.requires-direct-container-member` — `@SubContainer` is not a direct,
  plain, stored instance `var` in a supported `@DIContainer` struct. Move it
  into that container and remove accessors, storage modifiers, wrappers, and
  unknown attributes.
- `sub.conditional-declaration-unsupported` — the complete child declaration
  appears inside `#if`. Move it outside conditional compilation so storage,
  accessor, and parent-init macro phases cannot expand only part of the child.
- `sub.duplicate-attribute` — the property declares `@SubContainer` more than
  once. Keep exactly one child-container attribute.
- `sub.generated-accessor-manual-attachment` — InnoDI's hidden
  `_InnoDISubContainerAccessor` was attached manually. Remove it; the parent
  container owns this compiler support.
- `sub.unknown-scope` — the `scope:` value is not `.shared` or `.transient`.
- `sub.conflicts-with-provide` — a property can't carry both attributes.
- `sub.overrides-name-conflict` — generated child override helper storage
  would collide with an existing parent member name.
- `sub.unknown-parent-member` — `with:` key path doesn't map to a parent
  container member.
- `sub.unknown-child-input` — `bindings:` child key path doesn't map to a
  child input.
- `sub.bindings-conflicts-with-with` — `bindings:` and `with:` appear on the
  same `@SubContainer` (the wiring forms are mutually exclusive).
- `sub.invalid-same-name-wiring` — `with:` is not a literal key-path array the
  macro can read (runtime variables and computed elements are rejected).
- `sub.invalid-bindings` — `bindings:` is not a literal array of
  `(child:parent:)` key-path tuples.
- `sub.auto-wiring-ambiguous` — implicit same-name wiring cannot be
  inferred because the parent has multiple `@Provide` candidates. Add
  explicit `with:` / `bindings:`, or use `with: []` if the child takes no
  parent inputs.
- `sub.duplicate-child-binding` — the same child input is bound twice.
- `sub.shared-parent-must-not-be-transient` — `.shared` sub-container
  cannot read a `.transient` parent.

## Graph-level diagnostics (build plugin)

- `graph.dependency-cycle` — global DAG (across `@DIComponent` graph)
  detected a cycle.
- `graph.ambiguous-container-reference` — a name matched multiple
  containers.

## SwiftUI diagnostics

- `swiftui.feature-root-duplicate-default` — a `@SubContainer` declares more
  than one default feature root.
- `swiftui.feature-root-helper-name-conflict` — generated helper name
  collides with an existing member.
- `swiftui.feature-root-invalid-alias` — the feature-root alias argument
  cannot be parsed as a valid Swift identifier.
- `swiftui.feature-root-invalid-root` — a `featureRoot:` or `featureRoots:`
  entry does not use a root view type expression such as `RootView.self`.
- `swiftui.environment-bridge-unknown-member` — `@DIEnvironmentBridge`
  key path doesn't resolve to a container member.
- `swiftui.environment-bridge-duplicate-member` — the same key path is
  listed twice.
- `swiftui.environment-bridge-async-member` — an `asyncFactory`-backed
  container member was mapped into `EnvironmentValues`; expose a synchronous
  value or inject a service that performs async work internally.
- `swiftui.environment-bridge-invalid-keypath` — `environment:` is not a
  single direct-property key-path literal rooted at `EnvironmentValues` or
  `SwiftUI.EnvironmentValues`. Aliases, other roots, chains, and subscripts
  are rejected so generated code can preserve the key path without lexical
  capture.
- `swiftui.environment-bridge-invalid-arguments` — the bridge macro received
  arguments outside its supported key-path list shape.
- `swiftui.environment-bridge-reserved-module-name` — the bridge target, an
  enclosing nominal or generic parameter, or a direct nested type/typealias in
  the target named `Swift`, `SwiftUI`, or `InnoDISwiftUI` shadows a qualifier
  used by its generated modifier. Rename the type declaration or generic
  parameter. Value members with those names remain available. The required
  target-scoped full-source preflight extends the same diagnostic to visible
  declarations in sibling files, enclosing members, matching extensions, and
  imported dependency targets that an attached macro cannot inspect.
- `swiftui.environment-bridge-generated-name-conflict` — the bridge target
  redeclares a generated member. `_InnoDIEnvironmentBridgeModifier` conflicts
  with a direct nested nominal type, protocol, typealias, static/class
  variable or function, or enum case;
  `_innoDIEnvironmentBridgeModifier` conflicts only with a direct instance
  variable or zero-parameter instance function. Top-level `#if` branches are
  inspected recursively. Uppercase instance values/functions, lowercase
  static/class members, lowercase parameterized overloads, target and
  generic-parameter names, declarations in the opposite namespace, and
  declarations inside nested bodies remain available.
- `swiftui.environment-bridge-extension-context-unsupported` — the bridge
  target is an extension or is nested in an extension. Move it into file or
  nominal scope; an attached syntax macro cannot prove extension-member lookup
  across files before generating qualified SwiftUI support. The target-scoped
  full-source preflight emits this diagnostic for both forms before source
  compilation; without the required plugin, Swift may reject a direct
  extension attachment first.
- `swiftui.environment-bridge-local-declaration-unsupported` — the bridge
  target is declared inside a function, initializer, deinitializer, subscript,
  accessor, or closure. Move it to file or nominal scope so the generated
  conformance has a stable lookup path. This is a build/CLI full-source
  diagnostic because attached macros cannot reliably own that boundary before
  Swift diagnoses the local declaration.
- `swiftui.environment-bridge-unsupported-declaration-kind` — the bridge
  target is an actor, protocol, or another unsupported declaration kind. Move
  it to a struct, class, or enum.
- `swiftui.environment-bridge-private-nested-target` — the generated
  conformance path contains a `private` target or enclosing nominal nested in
  another type. Change that private lookup component to `fileprivate` or
  default access. A file-scope private target remains supported; its generated
  protocol witnesses are widened to `fileprivate`.
- `swiftui.environment-bridge-parameter-pack-unsupported` — the bridge target
  declares a generic parameter pack. Use ordinary generic parameters or put
  the bridge on a non-generic adapter type; InnoDI 5.0 fails closed instead of
  emitting a modifier that can trap in the Swift variadic-generics runtime.

## Component / Hierarchy diagnostics

- `component.escaped-target-unsupported` — an `@DIComponent` target uses a
  backtick-escaped identifier. Rename the type to an unescaped identifier so
  its generated `<Container>Dependencies` peer has one canonical Swift name.
  The peer macro owns this diagnostic; member and extension roles fail closed
  without emitting copies or malformed support declarations.
- `component.requires-container` — `@DIComponent` must be attached to a
  `@DIContainer`-marked type.
- `component.overrides-builder-required` — `@DIComponent` requires the
  synthesized overrides builder.
- `hierarchy-root.requires-container` — `@DIHierarchyRoot` must be
  attached to a `@DIContainer` type.

## Mock generation diagnostics

- `mock.requires-protocol` — `@GenerateMock` was attached to something
  other than a protocol declaration. Move the attribute to a protocol or
  remove it from a struct/class/enum.
- `mock.experimental-skeleton` — emitted as a note when the protocol
  declares no members. Confirms the macro plugin saw the attribute and
  produced the empty mock skeleton.
- `mock.unsupported-member` — one or more protocol requirements prevent
  synthesis (static/class requirements, subscripts, associated types,
  `inout` parameters, `rethrows` or typed `throws`, or opaque `some`
  return types). The diagnostic message lists up to five member names;
  implement those mocks manually until the next RFC 0001 stage lands.

See <doc:AutoMock> for the supported member shapes and the generated
storage layout.

## Preview macro diagnostics

- `swiftui.preview-with-container-missing-container` — `#PreviewWithContainer`
  was invoked without a container expression as its first argument.
- `swiftui.preview-with-container-missing-closure` — `#PreviewWithContainer`
  was invoked without a preview body closure.
- `swiftui.preview-with-container-missing-parameter` — the
  `#PreviewWithContainer` body closure did not declare the container
  parameter that the macro passes into the body.

## Internal diagnostics

- `internal.codegen-invariant` — the code generator encountered a case
  validation should have rejected. The message embeds the internal
  description; please file a bug with the full diagnostic text.
