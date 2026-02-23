#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GENERATED_ROOT="$ROOT_DIR/.build/generated-benchmarks/compile"
RESULT_PATH="$ROOT_DIR/Benchmarks/results/compile.json"
ITERATIONS=5
SIZES=(10 50 100 250)
SIZES_CSV=""
FRAMEWORKS=("InnoDI" "Needle" "SafeDI")

NEEDLE_VERSION="0.25.1"
SAFEDI_VERSION="1.5.1"

usage() {
  cat <<USAGE
Usage: Benchmarks/run-compile-bench.sh [options]

Options:
  --iterations <N>    Number of runs per scenario (default: 5)
  --sizes <CSV>       Comma-separated scenario sizes (default: 10,50,100,250)
  --output <PATH>     Output JSON file (default: Benchmarks/results/compile.json)
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
    --iterations)
      require_option_value "$1" "${2:-}"
      ITERATIONS="${2:-}"
      shift 2
      ;;
    --sizes)
      require_option_value "$1" "${2:-}"
      SIZES_CSV="${2:-}"
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

if ! [[ "$ITERATIONS" =~ ^[0-9]+$ ]] || [[ "$ITERATIONS" -lt 1 ]]; then
  echo "--iterations must be a positive integer" >&2
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
  if [[ "${#parsed_sizes[@]}" -eq 0 ]]; then
    echo "--sizes must include at least one value" >&2
    exit 1
  fi
  SIZES=("${parsed_sizes[@]}")
fi

mkdir -p "$GENERATED_ROOT" "$(dirname "$RESULT_PATH")"

measure_build_ms() {
  local dir="$1"
  local started ended

  (cd "$dir" && swift package clean >/dev/null 2>&1 || true)

  started="$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time()*1000000000')"
  (cd "$dir" && swift build -c release >/dev/null 2>&1)
  ended="$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time()*1000000000')"
  awk -v s="$started" -v e="$ended" 'BEGIN { printf "%.3f", (e - s) / 1000000.0 }'
}

json_array_from_samples() {
  local samples=("$@")
  local json="["
  local first=1
  for sample in "${samples[@]}"; do
    if [[ "$first" -eq 0 ]]; then
      json+=", "
    fi
    json+="$sample"
    first=0
  done
  json+="]"
  printf '%s' "$json"
}

mean_of_samples() {
  printf '%s\n' "$@" | awk '{sum += $1} END { if (NR == 0) { print 0 } else { printf "%.3f", sum / NR } }'
}

stdev_of_samples() {
  local mean="$1"
  shift
  printf '%s\n' "$@" | awk -v mean="$mean" '{sum += ($1 - mean)^2} END { if (NR <= 1) { printf "%.3f", 0 } else { printf "%.3f", sqrt(sum / (NR - 1)) } }'
}

needle_resolve_expression() {
  local size="$1"
  local expr="root"
  local i
  for ((i = 1; i <= size; i++)); do
    expr+=".component$i"
  done
  expr+=".service$size"
  printf '%s' "$expr"
}

prepare_needle_generated_code() {
  local dir="$1"
  (cd "$dir" && swift package resolve >/dev/null 2>&1)

  local needle_bin="$dir/.build/checkouts/needle/Generator/bin/needle"
  if [[ ! -x "$needle_bin" ]]; then
    echo "Needle generator not found at $needle_bin" >&2
    exit 1
  fi

  SOURCEKIT_LOGGING=0 "$needle_bin" generate \
    "$dir/Sources/BenchmarkApp/NeedleGenerated.swift" \
    "$dir/Sources" >/dev/null 2>&1
}

prepare_safedi_release_tool() {
  local dir="$1"
  (cd "$dir" && swift package resolve >/dev/null 2>&1)

  if ! (cd "$dir" && swift package --allow-network-connections all --allow-writing-to-package-directory safedi-release-install >/dev/null 2>&1); then
    echo "[compile-bench] warning: failed to install SafeDI release tool, falling back to default generator path" >&2
  fi
}

generate_innodi_project() {
  local size="$1"
  local dir="$GENERATED_ROOT/innodi-$size"
  mkdir -p "$dir/Sources/BenchmarkApp"

  cat >"$dir/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BenchmarkApp",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../../../")
    ],
    targets: [
        .executableTarget(
            name: "BenchmarkApp",
            dependencies: [
                .product(name: "InnoDI", package: "InnoDI")
            ]
        )
    ]
)
SWIFT

  {
    cat <<'SWIFT'
import InnoDI

SWIFT

    local i prev
    for ((i = 1; i <= size; i++)); do
      if [[ "$i" -eq 1 ]]; then
        echo "struct Service1 { let seed: Int; let depth: Int }"
      else
        prev=$((i - 1))
        echo "struct Service$i { let service$prev: Service$prev; let depth: Int }"
      fi
    done

    cat <<'SWIFT'

@DIContainer
struct BenchmarkContainer {
    @Provide(.input)
    var seed: Int
SWIFT

    for ((i = 1; i <= size; i++)); do
      if [[ "$i" -eq 1 ]]; then
        echo "    @Provide(.shared, Service1.self, with: [\\BenchmarkContainer.seed], concrete: true)"
      else
        prev=$((i - 1))
        echo "    @Provide(.shared, Service$i.self, with: [\\BenchmarkContainer.service$prev], concrete: true)"
      fi
      echo "    var service$i: Service$i"
      echo
    done

    cat <<SWIFT
}

func run() {
    let container = BenchmarkContainer(seed: 42)
    _ = container.service$size
}

run()
SWIFT
  } >"$dir/Sources/BenchmarkApp/main.swift"

  printf '%s' "$dir"
}

generate_needle_project() {
  local size="$1"
  local dir="$GENERATED_ROOT/needle-$size"
  mkdir -p "$dir/Sources/BenchmarkApp"

  cat >"$dir/Package.swift" <<SWIFT
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BenchmarkApp",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/uber/needle.git", from: "$NEEDLE_VERSION")
    ],
    targets: [
        .executableTarget(
            name: "BenchmarkApp",
            dependencies: [
                .product(name: "NeedleFoundation", package: "needle")
            ]
        )
    ]
)
SWIFT

  local resolve_expr
  resolve_expr="$(needle_resolve_expression "$size")"

  {
    cat <<'SWIFT'
import NeedleFoundation

public final class Seed {
    public let value: Int
    public init(value: Int) { self.value = value }
}

SWIFT

    local i prev next
    for ((i = 1; i <= size; i++)); do
      if [[ "$i" -eq 1 ]]; then
        cat <<'SWIFT'
public final class Service1 {
    public let depth: Int
    public init(seed: Seed) {
        self.depth = seed.value + 1
    }
}

SWIFT
      else
        prev=$((i - 1))
        cat <<SWIFT
public final class Service$i {
    public let depth: Int
    public init(service$prev: Service$prev) {
        self.depth = service$prev.depth + 1
    }
}

SWIFT
      fi
    done

    for ((i = 1; i <= size; i++)); do
      if [[ "$i" -eq 1 ]]; then
        cat <<'SWIFT'
public protocol Service1Dependency: Dependency {
    var seed: Seed { get }
}

SWIFT
      else
        prev=$((i - 1))
        cat <<SWIFT
public protocol Service${i}Dependency: Dependency {
    var service$prev: Service$prev { get }
}

SWIFT
      fi
    done

    cat <<'SWIFT'
public class RootComponent: BootstrapComponent {
    public var seed: Seed {
        return shared { Seed(value: 42) }
    }

SWIFT
    cat <<'SWIFT'
    public var component1: Service1Component {
        return shared { Service1Component(parent: self) }
    }
}

SWIFT

    for ((i = 1; i <= size; i++)); do
      if [[ "$i" -lt "$size" ]]; then
        next=$((i + 1))
      fi

      cat <<SWIFT
public class Service${i}Component: Component<Service${i}Dependency> {
    public var service$i: Service$i {
SWIFT
      if [[ "$i" -eq 1 ]]; then
        cat <<'SWIFT'
        return shared { Service1(seed: dependency.seed) }
SWIFT
      else
        prev=$((i - 1))
        cat <<SWIFT
        return shared { Service$i(service$prev: dependency.service$prev) }
SWIFT
      fi
      cat <<'SWIFT'
    }
SWIFT
      if [[ "$i" -lt "$size" ]]; then
        cat <<SWIFT

    public var component$next: Service${next}Component {
        return shared { Service${next}Component(parent: self) }
    }
}

SWIFT
      else
        cat <<'SWIFT'
}

SWIFT
      fi
    done

    cat <<SWIFT
func run() {
    registerProviderFactories()
    let root = RootComponent()
    _ = $resolve_expr.depth
}

run()
SWIFT
  } >"$dir/Sources/BenchmarkApp/main.swift"

  prepare_needle_generated_code "$dir"
  printf '%s' "$dir"
}

generate_safedi_project() {
  local size="$1"
  local dir="$GENERATED_ROOT/safedi-$size"
  mkdir -p "$dir/Sources/BenchmarkApp"

  cat >"$dir/Package.swift" <<SWIFT
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BenchmarkApp",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/dfed/SafeDI.git", from: "$SAFEDI_VERSION")
    ],
    targets: [
        .executableTarget(
            name: "BenchmarkApp",
            dependencies: ["SafeDI"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            plugins: [
                .plugin(name: "SafeDIGenerator", package: "SafeDI")
            ]
        )
    ]
)
SWIFT

  {
    cat <<'SWIFT'
import SafeDI

@Instantiable
public final class Seed: Instantiable {
    public let value: Int
    public init() {
        self.value = 42
    }
}

SWIFT

    local i prev
    for ((i = 1; i <= size; i++)); do
      if [[ "$i" -eq 1 ]]; then
        cat <<'SWIFT'
@Instantiable
public final class Service1: Instantiable {
    public let depth: Int
    public init(seed: Seed) {
        self.seed = seed
        self.depth = seed.value + 1
    }

    @Instantiated public let seed: Seed
}

SWIFT
      else
        prev=$((i - 1))
        cat <<SWIFT
@Instantiable
public final class Service$i: Instantiable {
    public let depth: Int
    public init(service$prev: Service$prev) {
        self.service$prev = service$prev
        self.depth = service$prev.depth + 1
    }

    @Instantiated public let service$prev: Service$prev
}

SWIFT
      fi
    done

    cat <<SWIFT
@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(service$size: Service$size) {
        self.service$size = service$size
    }

    @Instantiated public let service$size: Service$size
}

func run() {
    let root = Root()
    _ = root.service$size.depth
}

run()
SWIFT
  } >"$dir/Sources/BenchmarkApp/main.swift"

  prepare_safedi_release_tool "$dir"
  printf '%s' "$dir"
}

echo "[compile-bench] Iterations: $ITERATIONS"

result_entries=""
for framework in "${FRAMEWORKS[@]}"; do
  for size in "${SIZES[@]}"; do
    echo "[compile-bench] preparing framework=$framework size=$size"
    case "$framework" in
      InnoDI)
        project_dir="$(generate_innodi_project "$size")"
        ;;
      Needle)
        project_dir="$(generate_needle_project "$size")"
        ;;
      SafeDI)
        project_dir="$(generate_safedi_project "$size")"
        ;;
      *)
        echo "Unsupported framework: $framework" >&2
        exit 1
        ;;
    esac

    declare -a samples=()
    for run in $(seq 1 "$ITERATIONS"); do
      sample="$(measure_build_ms "$project_dir")"
      samples+=("$sample")
      echo "[compile-bench] framework=$framework size=$size run=$run/${ITERATIONS} ms=$sample"
    done

    mean_ms="$(mean_of_samples "${samples[@]}")"
    stdev_ms="$(stdev_of_samples "$mean_ms" "${samples[@]}")"
    samples_json="$(json_array_from_samples "${samples[@]}")"
    entry="{\"framework\":\"$framework\",\"size\":$size,\"iterations\":$ITERATIONS,\"samples_ms\":$samples_json,\"mean_ms\":$mean_ms,\"stdev_ms\":$stdev_ms}"

    if [[ -n "$result_entries" ]]; then
      result_entries+=","
    fi
    result_entries+="$entry"
  done
done

generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
sizes_json="$(json_array_from_samples "${SIZES[@]}")"
cat >"$RESULT_PATH" <<JSON
{
  "kind": "compile",
  "generated_at": "$generated_at",
  "iterations": $ITERATIONS,
  "sizes": $sizes_json,
  "results": [$result_entries]
}
JSON

echo "[compile-bench] Wrote $RESULT_PATH"
