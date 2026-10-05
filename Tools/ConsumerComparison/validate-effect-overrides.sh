#!/usr/bin/env bash
# DX correctness scenarios, NOT timing or API-equivalence claims.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEPENDENCIES="${1:?Pinned official swift-dependencies checkout}"
PLUGIN="${2:?Actual InnoDIMacros-tool}"
RUNTIME="${3:?Portable InnoDI module directory from validate-owned-portable-plugin.sh}"
OUT="${4:?Isolated output directory}"
mkdir -p "$OUT/Dependencies/Sources/Consumer"
OUT="$(cd "$OUT" && pwd)"
cp "$ROOT/Tools/ConsumerComparison/EffectOverride/Dependencies.swift.fixture" "$OUT/Dependencies/Sources/Consumer/Main.swift"
cat > "$OUT/Dependencies/Package.swift" <<MANIFEST
// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "EffectOverride", dependencies: [.package(path: "$DEPENDENCIES")], targets: [.executableTarget(name: "Consumer", dependencies: [.product(name: "Dependencies", package: "swift-dependencies")])])
MANIFEST
swift build --package-path "$OUT/Dependencies" --cache-path "$OUT/cache" --config-path "$OUT/config" \
  --security-path "$OUT/security" -c release -j 4 > "$OUT/dependencies-build.log" 2>&1
"$OUT/Dependencies/.build/release/Consumer" | tee "$OUT/dependencies-run.log"
cp "$ROOT/Tools/ConsumerComparison/EffectOverride/InnoDI.swift.fixture" "$OUT/InnoDI.swift"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -O -parse-as-library -module-name EffectInnoDI \
  -load-plugin-executable "$PLUGIN#InnoDIMacros" -I "$RUNTIME" -L "$RUNTIME" -lInnoDI \
  -Xlinker -rpath -Xlinker "$RUNTIME" "$OUT/InnoDI.swift" -o "$OUT/InnoDI" > "$OUT/innodi-build.log" 2>&1
"$OUT/InnoDI" | tee "$OUT/innodi-run.log"
