#!/usr/bin/env bash
set -euo pipefail
# Focused analysis microbenchmark, intentionally independent of Apple SDKs.
# Default: 30 paired samples, 3 warmups, N=20/50/200/1000, sparse+dense.
# Full macro/consumer builds and Apple tests remain separate required gates.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:-$ROOT/build/dependency-availability.json}"
mkdir -p "$(dirname "$OUTPUT")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc -O -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
    -package-name InnoDIAvailabilityBenchmark \
    "$ROOT/Sources/InnoDICore/DependencyAvailabilityIndex.swift" \
    "$ROOT/Tools/DependencyAvailabilityBenchmark.swift" \
    -o "$TMP/benchmark"
export INNODI_INDEX_SOURCE_SHA256
INNODI_INDEX_SOURCE_SHA256="$(python3 - "$ROOT" <<'PYHASH'
import hashlib,pathlib,sys
root=pathlib.Path(sys.argv[1])
print(hashlib.sha256((root/"Sources/InnoDICore/DependencyAvailabilityIndex.swift").read_bytes()).hexdigest())
PYHASH
)"
export INNODI_INDEX_CPU
INNODI_INDEX_CPU="$(python3 - <<'PYCPU'
import pathlib,platform,subprocess
cpu=platform.machine()+" "+platform.processor()
info=pathlib.Path("/proc/cpuinfo")
if info.exists():
    cpu += " " + next((line.split(":",1)[1].strip() for line in info.read_text().splitlines() if line.startswith("model name")), "")
elif platform.system()=="Darwin":
    cpu += " " + subprocess.check_output(["sysctl","-n","machdep.cpu.brand_string"],text=True).strip()
print(cpu.strip())
PYCPU
)"
SWIFT_VERSION="$(swiftc --version)" "$TMP/benchmark" > "$OUTPUT"
printf 'Wrote focused availability measurements to %s\n' "$OUTPUT"
