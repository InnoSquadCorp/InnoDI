#!/usr/bin/env bash
# Narrow Swift 6.4/Linux validation, not Apple release qualification.
# Run actual macro declarations through the real compiled plugin. This excludes
# the Apple-only legacy AsyncSharedCell, not replaces it. Not full package QA.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN="${1:?Pass the already built InnoDIMacros-tool executable}"
OUT="${2:?Pass an isolated output directory}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
FLAGS=(-swift-version 6 -strict-concurrency=complete -warnings-as-errors)
LOAD=(-load-plugin-executable "$PLUGIN#InnoDIMacros")
swiftc "${FLAGS[@]}" "${LOAD[@]}" -emit-module -emit-library -module-name InnoDI \
  -o "$OUT/libInnoDI.so" -emit-module-path "$OUT/InnoDI.swiftmodule" \
  "$ROOT/Sources/InnoDI/"{InnoDI,DITracing,OnDemandSharedCell,DIAsyncScope,DIAsyncOwner,DICollections}.swift \
  > "$OUT/runtime-module.log" 2>&1
cp "$ROOT/Tests/OwnedPortablePluginFixtures/Positive.swift.fixture" "$OUT/Positive.swift"
swiftc "${FLAGS[@]}" "${LOAD[@]}" -parse-as-library -I "$OUT" -L "$OUT" -lInnoDI \
  -Xlinker -rpath -Xlinker "$OUT" "$OUT/Positive.swift" -o "$OUT/Positive" \
  > "$OUT/positive-compile.log" 2>&1
"$OUT/Positive" > "$OUT/positive-run.log" 2>&1
cat "$OUT/positive-run.log"

cp "$ROOT/Tests/OwnedPortablePluginFixtures/Deferred.swift.fixture" "$OUT/Deferred.swift"
swiftc "${FLAGS[@]}" "${LOAD[@]}" -parse-as-library -I "$OUT" -L "$OUT" -lInnoDI \
  -Xlinker -rpath -Xlinker "$OUT" "$OUT/Deferred.swift" -o "$OUT/Deferred" \
  > "$OUT/deferred-compile.log" 2>&1
"$OUT/Deferred" > "$OUT/deferred-run.log" 2>&1
cat "$OUT/deferred-run.log"

# Legacy deferred captures keep Swift's isolation checking. These consumers
# cover non-Sendable synchronous handles, actor-local captures, ordinary
# Sendable async dependencies, and an exclusively transferred resolver.
for fixture in LegacyDeferredPositive LegacyDeferredTransfer LegacyDeferredBinding; do
  cp "$ROOT/Tests/OwnedPortablePluginFixtures/$fixture.swift.fixture" "$OUT/$fixture.swift"
  swiftc "${FLAGS[@]}" "${LOAD[@]}" -parse-as-library -I "$OUT" -L "$OUT" -lInnoDI \
    -Xlinker -rpath -Xlinker "$OUT" "$OUT/$fixture.swift" -o "$OUT/$fixture" \
    > "$OUT/$fixture-compile.log" 2>&1
  "$OUT/$fixture" > "$OUT/$fixture-run.log" 2>&1
  cat "$OUT/$fixture-run.log"
done

# Public generated APIs must also work across a real consumer module boundary.
cp "$ROOT/Tests/OwnedPortablePluginFixtures/PublicLibrary.swift.fixture" "$OUT/PublicLibrary.swift"
swiftc "${FLAGS[@]}" "${LOAD[@]}" -emit-module -emit-library -module-name OwnedPublicLibrary \
  -I "$OUT" -L "$OUT" -lInnoDI -Xlinker -rpath -Xlinker "$OUT" \
  -o "$OUT/libOwnedPublicLibrary.so" -emit-module-path "$OUT/OwnedPublicLibrary.swiftmodule" \
  "$OUT/PublicLibrary.swift" > "$OUT/public-library.log" 2>&1
cp "$ROOT/Tests/OwnedPortablePluginFixtures/PublicClient.swift.fixture" "$OUT/PublicClient.swift"
swiftc "${FLAGS[@]}" -parse-as-library -I "$OUT" -L "$OUT" -lInnoDI -lOwnedPublicLibrary \
  -Xlinker -rpath -Xlinker "$OUT" "$OUT/PublicClient.swift" -o "$OUT/PublicClient" \
  > "$OUT/public-client.log" 2>&1
"$OUT/PublicClient" > "$OUT/public-client-run.log" 2>&1
cat "$OUT/public-client-run.log"

# Source-written nonisolated(nonsending) properties preserve the caller's
# isolation across a real public module boundary; no new resolver API is needed.
cp "$ROOT/Tests/OwnedPortablePluginFixtures/CallerIsolatedLibrary.swift.fixture" "$OUT/CallerIsolatedLibrary.swift"
swiftc "${FLAGS[@]}" "${LOAD[@]}" -emit-module -emit-library -module-name CallerIsolatedLibrary \
  -I "$OUT" -L "$OUT" -lInnoDI -Xlinker -rpath -Xlinker "$OUT" \
  -o "$OUT/libCallerIsolatedLibrary.so" -emit-module-path "$OUT/CallerIsolatedLibrary.swiftmodule" \
  "$OUT/CallerIsolatedLibrary.swift" > "$OUT/caller-isolated-library.log" 2>&1
cp "$ROOT/Tests/OwnedPortablePluginFixtures/CallerIsolatedClient.swift.fixture" "$OUT/CallerIsolatedClient.swift"
swiftc "${FLAGS[@]}" -parse-as-library -I "$OUT" -L "$OUT" -lInnoDI -lCallerIsolatedLibrary \
  -Xlinker -rpath -Xlinker "$OUT" "$OUT/CallerIsolatedClient.swift" -o "$OUT/CallerIsolatedClient" \
  > "$OUT/caller-isolated-client.log" 2>&1
"$OUT/CallerIsolatedClient" > "$OUT/caller-isolated-client-run.log" 2>&1
cat "$OUT/caller-isolated-client-run.log"

# A source-written @MainActor must not be erased by async withOverrides helpers.
cp "$ROOT/Tests/OwnedPortablePluginFixtures/ExplicitActorOverrides.swift.fixture" "$OUT/ExplicitActorOverrides.swift"
swiftc "${FLAGS[@]}" "${LOAD[@]}" -parse-as-library -I "$OUT" -L "$OUT" -lInnoDI \
  -Xlinker -rpath -Xlinker "$OUT" "$OUT/ExplicitActorOverrides.swift" -o "$OUT/ExplicitActorOverrides" \
  > "$OUT/explicit-actor-overrides-compile.log" 2>&1
"$OUT/ExplicitActorOverrides" > "$OUT/explicit-actor-overrides-run.log" 2>&1
cat "$OUT/explicit-actor-overrides-run.log"

# Prepared-operation consumer coverage uses the real eager async storage on
# Linux. Exact on-demand coverage is wired into InnoDIRuntimeTests on Apple.
python3 "$ROOT/Tools/validate-prepared-fixture-parity.py"
for fixture in Prepared PreparedInputNames; do
  cp "$ROOT/Tests/OwnedPortablePluginFixtures/$fixture.swift.fixture" "$OUT/$fixture.swift"
  swiftc "${FLAGS[@]}" "${LOAD[@]}" -parse-as-library -I "$OUT" -L "$OUT" -lInnoDI \
    -Xlinker -rpath -Xlinker "$OUT" "$OUT/$fixture.swift" -o "$OUT/$fixture" \
    > "$OUT/$fixture-compile.log" 2>&1
  if timeout 40s "$OUT/$fixture" > "$OUT/$fixture-run.log" 2>&1; then
    cat "$OUT/$fixture-run.log"
  else
    status=$?
    cat "$OUT/$fixture-run.log" >&2
    if [[ "$status" == 124 ]]; then
      echo "$fixture exceeded its 40-second bound; unmatched pending resource release lines identify a release failure" >&2
    fi
    exit "$status"
  fi
done

negative() {
  local name="$1" source="$2" expected="$3"
  local mode=(-typecheck)
  if [[ "${4:-}" == "compile" ]]; then mode=(-c -o "$OUT/$name.o"); fi
  cp "$source" "$OUT/$name.swift"
  if swiftc "${FLAGS[@]}" "${LOAD[@]}" "${mode[@]}" -I "$OUT" "$OUT/$name.swift" > "$OUT/$name.log" 2>&1; then
    echo "Expected $name to fail" >&2; exit 1
  fi
  if grep -F 'Stack dump:' "$OUT/$name.log" >/dev/null; then
    cat "$OUT/$name.log" >&2; echo "Compiler crashed for $name" >&2; exit 1
  fi
  grep -F -- "$expected" "$OUT/$name.log" >/dev/null || {
    cat "$OUT/$name.log" >&2; echo "Missing expected diagnostic for $name" >&2; exit 1;
  }
  echo "Expected diagnostic passed: $name"
}
FIXTURES="$ROOT/Tests/OwnedPortablePluginFixtures"
negative CallerIsolatedHidden "$FIXTURES/CallerIsolatedHidden.swift.fixture" "inaccessible due to 'fileprivate' protection level" compile
negative CallerIsolatedActorEscape "$FIXTURES/CallerIsolatedActorEscape.swift.fixture" "non-Sendable type 'CallerIsolatedBox' of property 'session' cannot exit main actor-isolated context" compile

negative PreparedNoOwned "$FIXTURES/PreparedNoOwned.swift.fixture" "has no member 'withPrepared'" compile
negative PreparedNoAsync "$FIXTURES/PreparedNoAsync.swift.fixture" "has no member 'withPrepared'" compile
negative PreparedWrongContainer "$FIXTURES/PreparedWrongContainer.swift.fixture" "cannot convert value of type 'Second._InnoDIOwnedProvider'" compile
negative PreparedReservedName "$FIXTURES/PreparedReservedName.swift.fixture" "already uses 'withPrepared'" compile
negative SelfWitnessCollision "$FIXTURES/SelfWitnessCollision.swift.fixture" "uses the reserved generated prefix"
negative OwnedOverridesNameCollision "$FIXTURES/OwnedOverridesNameCollision.swift.fixture" "already uses 'makeOwnedWithOverrides'"
negative DeferredSendable "$FIXTURES/DeferredSendable.swift.fixture" "with non-Sendable type '_InnoDIDeferredCell<Int>'" compile
negative DeferredIndirectSendable "$FIXTURES/DeferredIndirectSendable.swift.fixture" "with non-Sendable type '_InnoDIDeferredCell<Int>'" compile
negative LegacyDeferredPayload "$FIXTURES/LegacyDeferredPayload.swift.fixture" "passing closure as a 'sending' parameter risks causing data races" compile
negative LegacyDeferredResolverCapture "$FIXTURES/LegacyDeferredResolverCapture.swift.fixture" "passing closure as a 'sending' parameter risks causing data races" compile
negative LegacyDeferredIndirectCapture "$FIXTURES/LegacyDeferredIndirectCapture.swift.fixture" "with non-Sendable type '_InnoDIDeferredCell<Int>'" compile
negative LegacyDeferredEagerCall "$FIXTURES/LegacyDeferredEagerCall.swift.fixture" "cannot call Lazy<T> during .shared construction" compile
negative LegacyDeferredProviderEagerCall "$FIXTURES/LegacyDeferredEagerCall.swift.fixture" "cannot call Provider<T> during .shared construction" compile
negative DeferredEagerCall "$FIXTURES/DeferredEagerCall.swift.fixture" "cannot call Lazy<T> during .shared construction"
negative DeferredCycle "$FIXTURES/DeferredCycle.swift.fixture" "Dependency cycle detected"
negative DeferredProviderCycle "$FIXTURES/DeferredProviderCycle.swift.fixture" "Dependency cycle detected"
negative DeferredProviderEagerCall "$FIXTURES/DeferredProviderEagerCall.swift.fixture" "cannot call Provider<T> during .shared construction"
negative DeferredAsyncTarget "$FIXTURES/DeferredAsyncTarget.swift.fixture" "Lazy resolvers are synchronous"
negative DeferredProviderTarget "$FIXTURES/DeferredProviderTarget.swift.fixture" "requires a .transient target"
negative DeferredWrongType "$FIXTURES/DeferredWrongType.swift.fixture" "cannot convert value of type 'Int' to closure result type 'String'"
negative DeferredUnknown "$FIXTURES/DeferredUnknown.swift.fixture" "does not match any injectable container member"
negative GenericContext "$FIXTURES/GenericContext.swift.fixture" "nested in generic context"
negative LegacySelfValue "$FIXTURES/LegacySelfValue.swift.fixture" "not a member type of"
negative PublicHidden "$FIXTURES/PublicHidden.swift.fixture" "inaccessible due to 'fileprivate' protection level"
EXTERNAL="$ROOT/Tests/ExternalConsumerFixtures/fail"
negative WrongContainer "$EXTERNAL/owned-wrong-container/Sources/FixtureApp/FixtureApp.swift.fixture" "cannot convert value of type"
negative WrongExecutor "$EXTERNAL/owned-wrong-executor/Sources/FixtureApp/FixtureApp.swift.fixture" "main actor-isolated property"
negative NotResolver "$EXTERNAL/owned-selection-not-resolver/Sources/FixtureApp/FixtureApp.swift.fixture" "has no member 'value'"
negative SharedTransientDependency "$FIXTURES/SharedTransientDependency.swift.fixture" "is not available in this construction scope because it is a transient provider"
negative ActorSharedTransientDependency "$FIXTURES/ActorSharedTransientDependency.swift.fixture" "is not available in this construction scope because it is a transient provider"
# Attribute names do not carry semantic actor identity for syntax macros. A
# custom actor without an Actor suffix remains unsupported and Swift rejects it.
negative UnknownActor "$FIXTURES/UnknownActor.swift.fixture" "global actor 'Domain'-isolated initializer"
