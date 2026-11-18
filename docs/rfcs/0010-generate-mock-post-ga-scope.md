# RFC 0010 — `@GenerateMock` scope after GA

- **Status**: Draft
- **Authors**: InnoDI maintainers
- **Created**: 2026-11-11
- **Last updated**: 2026-11-11
- **Target release**: none assigned
- **Related**: [RFC 0001](0001-macro-mock-generation.md)

## Summary

[RFC 0001](0001-macro-mock-generation.md) promoted `@GenerateMock` to GA for
7.1.0 with a fixed scope. This RFC holds the requirements that promotion left
out, so each one has a single place where its design can be settled. Nothing
here is scheduled or accepted.

## Deferred requirements

Every row is rejected today with `mock.unsupported-member` or is unimplemented.
The macro never emits a partial conformance for them.

| Requirement | State in 7.1.0 | Question to settle |
|---|---|---|
| Associated types | Rejected | How a consumer pins each associated type, for example `@GenerateMock(associatedTypes: ...)`, and how a constraint declared in another module resolves. |
| Custom global actors and individually isolated requirements | Rejected; protocol-level `@MainActor` is supported | Whether isolation other than `@MainActor` needs its own generation mode. |
| Protocol inheritance other than `AnyObject` and `Sendable` | Rejected, because an attached peer macro cannot see inherited requirements in other files or modules | Whether build support can supply the inherited requirements. |
| `static` and `class` requirements | Rejected | Where type-level stubs and call records live. |
| Opaque call records | A generated `Call` struct stores value types; a parameter it cannot store fails closed | Whether a fallback record that stores `Any` is worth losing `#expect` comparisons. |
| `bundleWithOverrides:` | Reserved and not implemented | How a generated mock is bundled into a container's `Overrides` builder. |

## Compatibility

Supporting one of these later is additive under the
[versioning policy](../../RELEASING.md#versioning-policy): a protocol that is
rejected today starts to generate a mock. It must not change the generated
shape of a protocol that already generates one, because that shape is covered
by semantic versioning from 7.1.0.

## Open questions

Each row of the table above is open. No design is preferred yet beyond the
candidate directions recorded in RFC 0001.
