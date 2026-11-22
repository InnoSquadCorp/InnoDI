# Semantic Resolution

Resolving type references against the known container namespace.

## Overview

When the macro sees `@SubContainer var child: FeatureContainer`, the
written name is usually a short identifier — but the build plugin needs
to match it against a fully-qualified semantic path (e.g.
`App.Feature.FeatureContainer`) to validate cross-module hierarchy
rules.

`SemanticResolverIndex` and its companion helpers (`SemanticResolution.swift`)
record nominal type records (path + components) and top-level typealiases
seen in the parsed sources. Consumers ask the index to:

- resolve a written reference to the set of candidate semantic paths,
- disambiguate between candidates using ownership-eligibility rules
  (only a container in scope can own another), and
- surface warnings when a reference is ambiguous or aliases to a
  non-container type.

## When to reach into this module

Only code inside the InnoDI package can construct `SemanticResolverIndex`:
it and its records are declared `package`, and `InnoDICore` is not a package
product. The dependency-graph CLI and the build plugin construct it, so
they share one set of resolution rules. A new validator inside the package
should reuse it instead of re-implementing those rules.

## Package Types

- `SemanticResolverIndex`
- `SemanticNominalTypeRecord`
