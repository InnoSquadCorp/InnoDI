#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GENERATED_ROOT="$ROOT_DIR/.build/generated-benchmarks/validation"
RESULT_PATH="$ROOT_DIR/Benchmarks/results/validation.json"
SCHEMA_VERSION=1
PRESET="local"
RUNS=3
SIZES=(10 50 100)
SIZES_CSV=""
RUNS_EXPLICIT=0
SIZES_EXPLICIT=0

usage() {
  cat <<USAGE
Usage: Benchmarks/run-validation-bench.sh [options]

Options:
  --preset <local|ci>  Benchmark preset (default: local)
  --runs <N>          Number of measured runs per scenario (default: 3)
  --sizes <CSV>       Comma-separated scenario sizes (default: 10,50,100)
  --output <PATH>     Output JSON file (default: Benchmarks/results/validation.json)
USAGE
}

require_option_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "$value" || "$value" == -* ]]; then
    echo "Missing value for $option" >&2
    usage
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preset)
      require_option_value "$1" "${2:-}"
      PRESET="${2:-}"
      shift 2
      ;;
    --runs)
      require_option_value "$1" "${2:-}"
      RUNS="${2:-}"
      RUNS_EXPLICIT=1
      shift 2
      ;;
    --sizes)
      require_option_value "$1" "${2:-}"
      SIZES_CSV="${2:-}"
      SIZES_EXPLICIT=1
      shift 2
      ;;
    --output)
      require_option_value "$1" "${2:-}"
      RESULT_PATH="${2:-}"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

case "$PRESET" in
  local)
    if [[ "$RUNS_EXPLICIT" -eq 0 ]]; then
      RUNS=3
    fi
    if [[ "$SIZES_EXPLICIT" -eq 0 ]]; then
      SIZES=(10 50 100)
    fi
    ;;
  ci)
    if [[ "$RUNS_EXPLICIT" -eq 0 ]]; then
      RUNS=1
    fi
    if [[ "$SIZES_EXPLICIT" -eq 0 ]]; then
      SIZES=(10 50)
    fi
    ;;
  *)
    echo "--preset must be one of: local, ci" >&2
    exit 1
    ;;
esac

if ! [[ "$RUNS" =~ ^[0-9]+$ ]] || [[ "$RUNS" -lt 1 ]]; then
  echo "--runs must be a positive integer" >&2
  exit 1
fi

if [[ -n "$SIZES_CSV" ]]; then
  IFS=',' read -r -a raw_sizes <<<"$SIZES_CSV"
  declare -a parsed_sizes=()
  for size in "${raw_sizes[@]}"; do
    size="${size//[[:space:]]/}"
    if ! [[ "$size" =~ ^[0-9]+$ ]] || [[ "$size" -lt 1 ]]; then
      echo "--sizes must be a comma-separated list of positive integers" >&2
      exit 1
    fi
    parsed_sizes+=("$size")
  done
  SIZES=("${parsed_sizes[@]}")
fi

mkdir -p "$GENERATED_ROOT" "$(dirname "$RESULT_PATH")"
TMP_RESULTS="$(mktemp)"
trap 'rm -f "$TMP_RESULTS"' EXIT

discover_executable() {
  local name="$1"
  local build_root="$ROOT_DIR/.build"
  local candidates=(
    "$build_root/debug/$name"
    "$build_root/arm64-apple-macosx/debug/$name"
    "$build_root/x86_64-apple-macosx/debug/$name"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  while IFS= read -r candidate; do
    if [[ -x "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done < <(find "$build_root" -path "*/debug/$name" -type f 2>/dev/null | sort)

  echo "Failed to locate executable $name" >&2
  exit 1
}

measure_ms() {
  local started ended status
  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"
  started="$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time()*1000000000')"
  set +e
  "$@" >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
  ended="$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time()*1000000000')"
  rm -f "$stdout_file" "$stderr_file"
  local elapsed
  elapsed="$(awk -v s="$started" -v e="$ended" 'BEGIN { printf "%.3f", (e - s) / 1000000.0 }')"
  printf '%s %s\n' "$elapsed" "$status"
}

write_common_models() {
  local dir="$1"
  cat >"$dir/Common.swift" <<'SWIFT'
import InnoDI

struct Config {
    let seed: Int
}

struct LeafService {
    let seed: Int
}
SWIFT
}

generate_nested_containers() {
  local dir="$1"
  local size="$2"
  write_common_models "$dir"
  {
    cat <<'SWIFT'
import InnoDI

@DIContainer(root: true)
struct AppContainer {
    @Provide(.input)
    var config: Config

SWIFT
    local i prev
    for ((i = 1; i <= size; i++)); do
      if [[ "$i" -eq 1 ]]; then
        echo "    @Provide(.shared, factory: Feature1.Container(config: config), concrete: true)"
      else
        prev=$((i - 1))
        echo "    @Provide(.shared, factory: Feature$i.Container(feature: feature$prev), concrete: true)"
      fi
      echo "    var feature$i: Feature$i.Container"
      echo
      cat <<SWIFT
enum Feature$i {
    @DIContainer
    struct Container {
SWIFT
      if [[ "$i" -eq 1 ]]; then
        echo "        @Provide(.input)"
        echo "        var config: Config"
        echo
        echo "        @Provide(.shared, factory: LeafService(seed: config.seed), concrete: true)"
        echo "        var leaf: LeafService"
      else
        prev=$((i - 1))
        echo "        @Provide(.input)"
        echo "        var feature: Feature$prev.Container"
        echo
        echo "        @Provide(.shared, factory: feature, concrete: true)"
        echo "        var upstream: Feature$prev.Container"
      fi
      cat <<'SWIFT'
    }
}

SWIFT
    done
    cat <<'SWIFT'
}
SWIFT
  } >"$dir/NestedContainers.swift"
}

generate_typealias_heavy() {
  local dir="$1"
  local size="$2"
  write_common_models "$dir"
  {
    cat <<'SWIFT'
import InnoDI

enum Namespace {
    @DIContainer
    struct LiveContainer {
        @Provide(.input)
        var config: Config
    }

    typealias ActiveContainer = LiveContainer
}

typealias RootAlias = Namespace.ActiveContainer

@DIContainer(root: true)
struct AppContainer {
    @Provide(.input)
    var config: Config

SWIFT
    local i
    for ((i = 1; i <= size; i++)); do
      echo "    @Provide(.shared, factory: RootAlias(config: config), concrete: true)"
      echo "    var feature$i: Namespace.LiveContainer"
      echo
    done
    cat <<'SWIFT'
}
SWIFT
  } >"$dir/TypeAliasHeavy.swift"
}

generate_duplicate_display_names() {
  local dir="$1"
  write_common_models "$dir"
  cat >"$dir/DuplicateDisplayNames.swift" <<'SWIFT'
import InnoDI

@DIContainer(root: true)
struct AppContainer {
    @Provide(.input)
    var config: Config

    @Provide(.shared, factory: FeatureContainer(config: config), concrete: true)
    var feature: FeatureContainer
}

enum FeatureA {
    @DIContainer
    struct FeatureContainer {
        @Provide(.input)
        var config: Config
    }
}

enum FeatureB {
    @DIContainer
    struct FeatureContainer {
        @Provide(.input)
        var config: Config
    }
}
SWIFT
}

generate_unresolved_semantic() {
  local dir="$1"
  write_common_models "$dir"
  cat >"$dir/UnresolvedSemantic.swift" <<'SWIFT'
import InnoDI

@DIContainer(root: true)
struct AppContainer {
    @Provide(.input)
    var config: Config

    @Provide(.shared, factory: MissingFeatureContainer(config: config), concrete: true)
    var feature: MissingFeatureContainer
}
SWIFT
}

mutate_content_change() {
  local dir="$1"
  python3 - "$dir/NestedContainers.swift" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
path.write_text(text.replace("LeafService(seed: config.seed)", "LeafService(seed: config.seed + 1)", 1))
PY
}

mutate_add_delete() {
  local dir="$1"
  cat >"$dir/AddedFile.swift" <<'SWIFT'
struct AddedFileMarker {
    let value = 1
}
SWIFT
  rm -f "$dir/Common.swift"
}

record_json_line() {
  local scenario="$1"
  local size="$2"
  local run="$3"
  local graph_ms="$4"
  local graph_exit="$5"
  local cold_ms="$6"
  local cold_exit="$7"
  local warm_ms="$8"
  local warm_exit="$9"
  local mutation_kind="${10}"
  local mutation_ms="${11}"
  local mutation_exit="${12}"
  local artifact_path="${13}"

  python3 - "$scenario" "$size" "$run" "$graph_ms" "$graph_exit" "$cold_ms" "$cold_exit" "$warm_ms" "$warm_exit" "$mutation_kind" "$mutation_ms" "$mutation_exit" "$artifact_path" >>"$TMP_RESULTS" <<'PY'
import json, sys
from pathlib import Path

scenario, size, run, graph_ms, graph_exit, cold_ms, cold_exit, warm_ms, warm_exit, mutation_kind, mutation_ms, mutation_exit, artifact_path = sys.argv[1:]
artifact = {}
path = Path(artifact_path)
if path.exists():
    artifact = json.loads(path.read_text())

entry = {
    "scenario": scenario,
    "size": int(size),
    "run": int(run),
    "graph_scan_ms": float(graph_ms),
    "graph_exit_code": int(graph_exit),
    "coordinator_cold_ms": float(cold_ms),
    "coordinator_cold_exit_code": int(cold_exit),
    "coordinator_warm_ms": float(warm_ms),
    "coordinator_warm_exit_code": int(warm_exit),
    "warm_reason_codes": artifact.get("reasonCodes", []),
    "warm_human_summary_source": artifact.get("humanSummarySource"),
    "warm_file_changes": artifact.get("fileChanges", {}),
}
if mutation_kind != "none":
    entry["mutation"] = {
        "kind": mutation_kind,
        "ms": float(mutation_ms),
        "exit_code": int(mutation_exit),
    }
print(json.dumps(entry))
PY
}

echo "[validation-bench] Building validation tools"
(cd "$ROOT_DIR" && swift build --product InnoDI-DependencyGraph --product InnoDI-DAGValidationCoordinator >/dev/null)

GRAPH_TOOL="$(discover_executable InnoDI-DependencyGraph)"
COORDINATOR_TOOL="$(discover_executable InnoDI-DAGValidationCoordinator)"

run_scenario() {
  local scenario="$1"
  local size="$2"
  local run="$3"
  local dir="$GENERATED_ROOT/$scenario-$size-run$run"
  local state_dir="$dir/state"
  local output_cold="$dir/output-cold"
  local output_warm="$dir/output-warm"
  local output_mutation="$dir/output-mutation"
  rm -rf "$dir"
  mkdir -p "$dir" "$state_dir" "$output_cold" "$output_warm" "$output_mutation"

  case "$scenario" in
    nested-containers)
      generate_nested_containers "$dir" "$size"
      ;;
    typealias-heavy)
      generate_typealias_heavy "$dir" "$size"
      ;;
    duplicate-display-names)
      generate_duplicate_display_names "$dir"
      ;;
    unresolved-semantic)
      generate_unresolved_semantic "$dir"
      ;;
    cache-content-change)
      generate_nested_containers "$dir" "$size"
      ;;
    cache-add-delete)
      generate_nested_containers "$dir" "$size"
      ;;
    *)
      echo "Unknown scenario: $scenario" >&2
      exit 1
      ;;
  esac

  read -r graph_ms graph_exit < <(measure_ms "$GRAPH_TOOL" --root "$dir" --validate-dag)
  read -r cold_ms cold_exit < <(measure_ms "$COORDINATOR_TOOL" --root "$dir" --tool "$GRAPH_TOOL" --state-dir "$state_dir" --output-dir "$output_cold")
  read -r warm_ms warm_exit < <(measure_ms "$COORDINATOR_TOOL" --root "$dir" --tool "$GRAPH_TOOL" --state-dir "$state_dir" --output-dir "$output_warm")

  local mutation_kind="none"
  local mutation_ms="0.000"
  local mutation_exit="0"
  if [[ "$scenario" == "cache-content-change" ]]; then
    mutate_content_change "$dir"
    mutation_kind="content-change"
    read -r mutation_ms mutation_exit < <(measure_ms "$COORDINATOR_TOOL" --root "$dir" --tool "$GRAPH_TOOL" --state-dir "$state_dir" --output-dir "$output_mutation")
  elif [[ "$scenario" == "cache-add-delete" ]]; then
    mutate_add_delete "$dir"
    mutation_kind="add-delete"
    read -r mutation_ms mutation_exit < <(measure_ms "$COORDINATOR_TOOL" --root "$dir" --tool "$GRAPH_TOOL" --state-dir "$state_dir" --output-dir "$output_mutation")
  fi

  record_json_line \
    "$scenario" "$size" "$run" \
    "$graph_ms" "$graph_exit" \
    "$cold_ms" "$cold_exit" \
    "$warm_ms" "$warm_exit" \
    "$mutation_kind" "$mutation_ms" "$mutation_exit" \
    "$output_warm/dag-validation-metrics.json"
}

SCENARIOS=(
  "nested-containers"
  "typealias-heavy"
  "duplicate-display-names"
  "unresolved-semantic"
  "cache-content-change"
  "cache-add-delete"
)

for size in "${SIZES[@]}"; do
  for scenario in "${SCENARIOS[@]}"; do
    for ((run = 1; run <= RUNS; run++)); do
      echo "[validation-bench] scenario=$scenario size=$size run=$run"
      run_scenario "$scenario" "$size" "$run"
    done
  done
done

python3 - "$TMP_RESULTS" "$RESULT_PATH" "$RUNS" "${SIZES[*]}" "$PRESET" <<'PY'
import json, sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
import subprocess

tmp_path, result_path, runs, sizes, preset = sys.argv[1:]
rows = [json.loads(line) for line in Path(tmp_path).read_text().splitlines() if line.strip()]
grouped = defaultdict(list)
for row in rows:
    grouped[(row["scenario"], row["size"])].append(row)

def stats(values):
    if not values:
        return {"iterations": 0, "mean": 0, "min": 0, "max": 0, "samples": []}
    return {
        "iterations": len(values),
        "mean": round(sum(values) / len(values), 3),
        "min": round(min(values), 3),
        "max": round(max(values), 3),
        "samples": [round(v, 3) for v in values],
    }

def sorted_unique(sequence):
    return sorted(set(sequence))

def shell(command):
    try:
        return subprocess.check_output(command, text=True).strip()
    except Exception:
        return ""

scenarios = []
for (scenario, size), items in sorted(grouped.items()):
    warm_reason_counter = Counter()
    mutation_kind = None
    mutation_samples = []
    for item in items:
        warm_reason_counter.update(item.get("warm_reason_codes", []))
        if "mutation" in item:
            mutation_kind = item["mutation"]["kind"]
            mutation_samples.append(item["mutation"]["ms"])

    scenarios.append({
        "scenario": scenario,
        "size": size,
        "graph_scan": stats([item["graph_scan_ms"] for item in items]),
        "coordinator_cold": stats([item["coordinator_cold_ms"] for item in items]),
        "coordinator_warm": stats([item["coordinator_warm_ms"] for item in items]),
        "graph_exit_codes": sorted({item["graph_exit_code"] for item in items}),
        "warm_exit_codes": sorted({item["coordinator_warm_exit_code"] for item in items}),
        "warm_reason_frequencies": dict(sorted(warm_reason_counter.items())),
        "warm_file_change_sample": items[0].get("warm_file_changes", {}),
        "mutation": None if mutation_kind is None else {
            "kind": mutation_kind,
            "stats": stats(mutation_samples),
            "exit_codes": sorted({item["mutation"]["exit_code"] for item in items if "mutation" in item}),
        }
    })

payload = {
    "kind": "validation",
    "schema_version": 1,
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "swift_version": shell(["swift", "--version"]).splitlines()[0] if shell(["swift", "--version"]) else "",
    "config": {
        "preset": preset,
        "runs": int(runs),
        "sizes": [int(value) for value in sizes.split()],
        "scenarios": sorted_unique(row["scenario"] for row in rows),
    },
    "validation": scenarios,
}
Path(result_path).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

echo "[validation-bench] Wrote $RESULT_PATH"
