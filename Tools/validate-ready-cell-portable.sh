#!/usr/bin/env bash
# Swift 6.4/Linux process regressions. RuntimeSupport.swift must be the exact
# trap/error declarations exported by ConsumerComparisonExportTests.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?Pass an isolated output directory}"
SUPPORT="${2:?Pass exported RuntimeSupport.swift}"
CELL="${3:-$ROOT/Sources/InnoDI/OnDemandSharedCell.swift}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
for mode in debug release; do
  mkdir -p "$OUT/$mode"
  FLAGS=(-swift-version 6 -strict-concurrency=complete -warnings-as-errors)
  if [[ "$mode" = release ]]; then FLAGS+=(-O); fi
  swiftc "${FLAGS[@]}" -emit-module -emit-library -module-name InnoDI \
    -o "$OUT/$mode/libInnoDI.so" -emit-module-path "$OUT/$mode/InnoDI.swiftmodule" \
    "$ROOT/Sources/InnoDI/DITracing.swift" "$CELL" "$SUPPORT" \
    > "$OUT/$mode/module.log" 2>&1
  cp "$ROOT/Tests/OwnedPortablePluginFixtures/ReadyReentry.swift.fixture" "$OUT/$mode/Reentry.swift"
  swiftc "${FLAGS[@]}" -parse-as-library -I "$OUT/$mode" -L "$OUT/$mode" -lInnoDI \
    -Xlinker -rpath -Xlinker "$OUT/$mode" "$OUT/$mode/Reentry.swift" -o "$OUT/$mode/Reentry" \
    > "$OUT/$mode/compile.log" 2>&1
done
python3 - "$OUT" <<'PY'
import json,pathlib,resource,subprocess,sys
root=pathlib.Path(sys.argv[1]);results=[]
for optimization in ['debug','release']:
    for mode in ['factory','factory-release','trace']:
        def no_core(): resource.setrlimit(resource.RLIMIT_CORE,(0,0))
        result=subprocess.run([str(root/optimization/'Reentry'),mode],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=10,preexec_fn=no_core)
        (root/optimization/f'{mode}.log').write_text(result.stdout)
        assert result.returncode != 0 and 'Reentrant on-demand provider resolution detected' in result.stdout
        results.append({'optimization':optimization,'mode':mode,'exit':result.returncode,'expected_reentry_trap':True,'timed_out':False})
(root/'results.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps(results))
PY
