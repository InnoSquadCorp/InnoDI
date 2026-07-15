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
            if [[ "$line" == '```swift' || "$line" == '```swift '* ]]; then
                count=$((count + 1))
                current="$SNIPPET_DIR/$(printf '%03d' "$count").swift"
                {
                    printf '// Source: %s:%d\n' "$file" "$line_no"
                    printf '\n'
                } > "$current"
                in_block=true
                marked=false
            elif [[ "$line" =~ ^[[:space:]]*$ ]]; then
                :
            else
                echo "Expected marked Swift code block after innodi:compile marker in $file:$line_no" >&2
                exit 1
            fi
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
    if [[ "$marked" == true ]]; then
        echo "Missing marked Swift code block after innodi:compile marker in $file" >&2
        exit 1
    fi
}

while IFS= read -r file; do
    extract_snippets "$file"
done < <(
    {
        # All canonical and localized README files plus the in-repo docs
        # tree, including DocC interactive tutorials. Localized READMEs ride
        # the same gate so a structural divergence in their marked snippets
        # surfaces as a build failure.
        find . -maxdepth 1 -type f -name 'README*.md'
        find Sources/InnoDI/InnoDI.docc docs -type f \( -name '*.md' -o -name '*.tutorial' \)
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

package_dir="$TMP_DIR/package"
mkdir -p "$package_dir/Sources"

for snippet in "${snippets[@]}"; do
    target_name="DocSnippet$(basename "$snippet" .swift)"
    mkdir -p "$package_dir/Sources/$target_name"
    cp "$snippet" "$package_dir/Sources/$target_name/main.swift"
done

# Build every snippet as an isolated executable target in one package. This
# preserves module isolation between examples while compiling InnoDI and
# SwiftSyntax only once. Avoid a large here-document: Bash 5.3 on macOS can
# block while feeding one to an external command before that command reads.
{
    printf '%s\n' '// swift-tools-version: 6.2'
    printf '%s\n' 'import PackageDescription'
    printf '\n'
    printf '%s\n' 'let package = Package('
    printf '%s\n' '    name: "InnoDIDocSnippets",'
    printf '%s\n' '    platforms: ['
    printf '%s\n' '        .iOS(.v17),'
    printf '%s\n' '        .macOS(.v13),'
    printf '%s\n' '        .watchOS(.v10),'
    printf '%s\n' '        .tvOS(.v17),'
    printf '%s\n' '        .visionOS(.v1),'
    printf '%s\n' '    ],'
    printf '%s\n' '    dependencies: ['
    printf '        .package(path: "%s"),\n' "$root_path_escaped"
    printf '%s\n' '    ],'
    printf '%s\n' '    targets: ['
    for snippet in "${snippets[@]}"; do
        target_name="DocSnippet$(basename "$snippet" .swift)"
        printf '%s\n' '        .executableTarget('
        printf '            name: "%s",\n' "$target_name"
        printf '%s\n' '            dependencies: ['
        printf '%s\n' '                .product(name: "InnoDI", package: "InnoDI"),'
        printf '%s\n' '                .product(name: "InnoDISwiftUI", package: "InnoDI"),'
        printf '%s\n' '            ]'
        printf '%s\n' '        ),'
    done
    printf '%s\n' '    ]'
    printf '%s\n' ')'
} > "$package_dir/Package.swift"

for snippet in "${snippets[@]}"; do
    echo "Checking $(sed -n '1s|// Source: ||p' "$snippet")"
done

swift build \
    --package-path "$package_dir" \
    -Xswiftc -strict-concurrency=complete \
    -Xswiftc -warnings-as-errors

echo "Checked ${#snippets[@]} marked Swift documentation snippet(s)."
