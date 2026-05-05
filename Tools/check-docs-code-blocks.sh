#!/usr/bin/env bash
# CI guard: Swift snippets marked with `<!-- innodi:compile -->` must compile
# against the local package. Unmarked snippets remain illustrative.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="$(mktemp -d)"
SNIPPET_DIR="$TMP_DIR/snippets"
mkdir -p "$SNIPPET_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

count=0
extract_snippets() {
    local file="$1"
    local marked=false
    local in_block=false
    local current=""
    local line_no=0
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_no=$((line_no + 1))

        if [[ "$in_block" == true ]]; then
            case "$line" in
                '```')
                    in_block=false
                    current=""
                    ;;
                *)
                    printf '%s\n' "$line" >> "$current"
                    ;;
            esac
            continue
        fi

        if [[ "$marked" == true ]]; then
            case "$line" in
                '```swift'|'```swift '*)
                    count=$((count + 1))
                    current="$SNIPPET_DIR/$(printf '%03d' "$count").swift"
                    {
                        printf '// Source: %s:%d\n' "$file" "$line_no"
                        printf '\n'
                    } > "$current"
                    in_block=true
                    ;;
            esac
            marked=false
            continue
        fi

        if [[ "$line" == "<!-- innodi:compile -->" ]]; then
            marked=true
        fi
    done < "$file"

    if [[ "$in_block" == true ]]; then
        echo "Unclosed marked Swift code block in $file" >&2
        exit 1
    fi
}

while IFS= read -r file; do
    extract_snippets "$file"
done < <(
    {
        printf '%s\n' "README.md"
        find Sources/InnoDI/InnoDI.docc docs -type f -name '*.md'
    } | sort -u
)

shopt -s nullglob
snippets=("$SNIPPET_DIR"/*.swift)
if [[ ${#snippets[@]} -eq 0 ]]; then
    echo "No marked Swift documentation snippets found."
    exit 0
fi

root_path_escaped="${ROOT_DIR//\\/\\\\}"
root_path_escaped="${root_path_escaped//\"/\\\"}"

for snippet in "${snippets[@]}"; do
    package_dir="$TMP_DIR/package-$(basename "$snippet" .swift)"
    mkdir -p "$package_dir/Sources/DocSnippet"
    cp "$snippet" "$package_dir/Sources/DocSnippet/main.swift"

    cat > "$package_dir/Package.swift" <<EOF
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InnoDIDocSnippet",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
        .watchOS(.v10),
        .tvOS(.v17),
        .visionOS(.v1),
    ],
    dependencies: [
        .package(path: "$root_path_escaped"),
    ],
    targets: [
        .executableTarget(
            name: "DocSnippet",
            dependencies: [
                .product(name: "InnoDI", package: "InnoDI"),
                .product(name: "InnoDISwiftUI", package: "InnoDI"),
            ]
        ),
    ]
)
EOF

    echo "Checking $(sed -n '1s|// Source: ||p' "$snippet")"
    swift build \
        --package-path "$package_dir" \
        -Xswiftc -strict-concurrency=complete \
        -Xswiftc -warnings-as-errors
done

echo "Checked ${#snippets[@]} marked Swift documentation snippet(s)."
