#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GENERATED_ROOT="$ROOT_DIR/.build/generated-benchmarks/runtime"
RESULT_PATH="$ROOT_DIR/Benchmarks/results/runtime.json"
SAMPLE_RUNS=5
RESOLVE_ITERATIONS=100000
SIZES=(10 50 100 250)
SIZES_CSV=""
FRAMEWORKS=("InnoDI" "Needle" "SafeDI")

NEEDLE_VERSION="0.25.1"
SAFEDI_VERSION="1.5.1"

usage() {
  cat <<USAGE
Usage: Benchmarks/run-runtime-bench.sh [options]

Options:
  --runs <N>          Number of measured runs per scenario (default: 5)
  --iterations <N>    Resolve loop count per run (default: 100000)
  --sizes <CSV>       Comma-separated scenario sizes (default: 10,50,100,250)
  --output <PATH>     Output JSON file (default: Benchmarks/results/runtime.json)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs)
      SAMPLE_RUNS="$2"
      shift 2
      ;;
    --iterations)
      RESOLVE_ITERATIONS="$2"
      shift 2
      ;;
    --sizes)
      SIZES_CSV="$2"
      shift 2
      ;;
    --output)
      RESULT_PATH="$2"
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

if ! [[ "$SAMPLE_RUNS" =~ ^[0-9]+$ ]] || [[ "$SAMPLE_RUNS" -lt 1 ]]; then
  echo "--runs must be a positive integer" >&2
  exit 1
fi

if ! [[ "$RESOLVE_ITERATIONS" =~ ^[0-9]+$ ]] || [[ "$RESOLVE_ITERATIONS" -lt 1 ]]; then
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

percentile_of_samples() {
  local quantile="$1"
  shift
  printf '%s\n' "$@" | sort -n | awk -v q="$quantile" '
    { values[NR] = $1 }
    END {
      if (NR == 0) { printf "0.000"; exit }
      raw = q * (NR - 1)
      low = int(raw)
      high = (raw > low) ? low + 1 : low
      if (high >= NR) { high = NR - 1 }
      frac = raw - low
      lower = values[low + 1]
      upper = values[high + 1]
      printf "%.3f", lower + (upper - lower) * frac
    }
  '
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
    echo "[runtime-bench] warning: failed to install SafeDI release tool, falling back to default generator path" >&2
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
import Foundation
import InnoDI

SWIFT

    local i prev
    for ((i = 1; i <= size; i++)); do
      if [[ "$i" -eq 1 ]]; then
        cat <<'SWIFT'
struct Service1 {
    let seed: Int
    let depth: Int

    init(seed: Int) {
        self.seed = seed
        self.depth = seed + 1
    }
}
SWIFT
      else
        prev=$((i - 1))
        cat <<SWIFT
struct Service$i {
    let service$prev: Service$prev
    let depth: Int

    init(service$prev: Service$prev) {
        self.service$prev = service$prev
        self.depth = service$prev.depth + 1
    }
}
SWIFT
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

@main
enum Main {
    @inline(never)
    static func consume(_ value: Service$size) -> Int {
        value.depth
    }

    static func main() {
        let iterations = Int(CommandLine.arguments.dropFirst().first ?? "100000") ?? 100000
        let container = BenchmarkContainer(seed: 42)
        var checksum = consume(container.service$size)

        let started = DispatchTime.now().uptimeNanoseconds
        for i in 0..<iterations {
            checksum &+= consume(container.service$size) &+ (i & 1)
        }
        let ended = DispatchTime.now().uptimeNanoseconds
        let nsPerOp = Double(ended - started) / Double(iterations)
        print(String(format: "%.3f", nsPerOp))
        if checksum == .min {
            print("unreachable \\(checksum)")
        }
    }
}
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
import Foundation
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
@inline(never)
func consume(_ value: Service$size) -> Int {
    value.depth
}

func resolveFinalService(_ root: RootComponent) -> Service$size {
    return $resolve_expr
}

func run() {
    let iterations = Int(CommandLine.arguments.dropFirst().first ?? "100000") ?? 100000
    registerProviderFactories()
    let root = RootComponent()
    var checksum = consume(resolveFinalService(root))

    let started = DispatchTime.now().uptimeNanoseconds
    for i in 0..<iterations {
        checksum &+= consume(resolveFinalService(root)) &+ (i & 1)
    }
    let ended = DispatchTime.now().uptimeNanoseconds
    let nsPerOp = Double(ended - started) / Double(iterations)
    print(String(format: "%.3f", nsPerOp))
    if checksum == .min {
        print("unreachable \\(checksum)")
    }
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
import Foundation
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

@inline(never)
func consume(_ value: Service$size) -> Int {
    value.depth
}

func run() {
    let iterations = Int(CommandLine.arguments.dropFirst().first ?? "100000") ?? 100000
    let root = Root()
    var checksum = consume(root.service$size)

    let started = DispatchTime.now().uptimeNanoseconds
    for i in 0..<iterations {
        checksum &+= consume(root.service$size) &+ (i & 1)
    }
    let ended = DispatchTime.now().uptimeNanoseconds
    let nsPerOp = Double(ended - started) / Double(iterations)
    print(String(format: "%.3f", nsPerOp))
    if checksum == .min {
        print("unreachable \\(checksum)")
    }
}

run()
SWIFT
  } >"$dir/Sources/BenchmarkApp/main.swift"

  prepare_safedi_release_tool "$dir"
  printf '%s' "$dir"
}

run_runtime_sample_ns() {
  local dir="$1"
  local iterations="$2"
  (cd "$dir" && swift run -c release BenchmarkApp "$iterations" 2>/dev/null)
}

echo "[runtime-bench] runs=$SAMPLE_RUNS iterations=$RESOLVE_ITERATIONS"

result_entries=""
for framework in "${FRAMEWORKS[@]}"; do
  for size in "${SIZES[@]}"; do
    echo "[runtime-bench] preparing framework=$framework size=$size"
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

    (cd "$project_dir" && swift build -c release >/dev/null 2>&1)

    run_runtime_sample_ns "$project_dir" "$RESOLVE_ITERATIONS" >/dev/null

    declare -a samples=()
    for run in $(seq 1 "$SAMPLE_RUNS"); do
      sample="$(run_runtime_sample_ns "$project_dir" "$RESOLVE_ITERATIONS")"
      samples+=("$sample")
      echo "[runtime-bench] framework=$framework size=$size run=$run/$SAMPLE_RUNS ns_per_op=$sample"
    done

    mean_ns="$(mean_of_samples "${samples[@]}")"
    p50_ns="$(percentile_of_samples 0.50 "${samples[@]}")"
    p95_ns="$(percentile_of_samples 0.95 "${samples[@]}")"
    samples_json="$(json_array_from_samples "${samples[@]}")"
    entry="{\"framework\":\"$framework\",\"size\":$size,\"runs\":$SAMPLE_RUNS,\"iterations_per_run\":$RESOLVE_ITERATIONS,\"samples_ns_per_op\":$samples_json,\"mean_ns_per_op\":$mean_ns,\"p50_ns_per_op\":$p50_ns,\"p95_ns_per_op\":$p95_ns}"

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
  "kind": "runtime",
  "generated_at": "$generated_at",
  "runs": $SAMPLE_RUNS,
  "iterations_per_run": $RESOLVE_ITERATIONS,
  "sizes": $sizes_json,
  "results": [$result_entries]
}
JSON

echo "[runtime-bench] Wrote $RESULT_PATH"
