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

Most code never needs to construct `SemanticResolverIndex` directly —
the dependency-graph CLI and the build plugin already do. Third-party
consumers that want to run custom validators (e.g. "no container may
import FooService directly") can reuse this machinery to share the same
resolution rules instead of re-implementing them.

## Topics

### Types

- `SemanticResolverIndex`
- `SemanticNominalTypeRecord`
