#!/usr/bin/env python3
"""Compile and execute exact public deferred examples and early README examples.

Requires a freshly built InnoDI module/library and matching macro plugin. This
is an executable documentation check, not a package/build-plugin or Apple SDK
qualification. Output retains the extracted Swift, logs, and source hashes.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swiftc", default="swiftc")
    parser.add_argument("--plugin", required=True, type=Path)
    parser.add_argument("--module-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    module_dir = args.module_dir.resolve()
    plugin = args.plugin.resolve()
    flags = [args.swiftc, "-swift-version", "6", "-strict-concurrency=complete",
             "-warnings-as-errors", "-module-cache-path", str(output / "module-cache"),
             "-load-plugin-executable", str(plugin) + "#InnoDIMacros",
             "-I", str(module_dir), "-L", str(module_dir), "-lInnoDI",
             "-Xlinker", "-rpath", "-Xlinker", str(module_dir)]
    rows = []

    def run(name, command):
        result = subprocess.run(command, capture_output=True, text=True, timeout=120)
        (output / (name + ".log")).write_text(result.stdout + result.stderr)
        rows.append({"name": name, "command": command, "exit": result.returncode})
        if result.returncode:
            raise RuntimeError(f"{name} failed; see {output / (name + '.log')}")
        return result.stdout

    def execute(name, source, library=False):
        path = output / (name + ".swift")
        path.write_text(source)
        binary = output / name
        run(name + "-compile", flags + (["-parse-as-library"] if library else [])
            + [str(path), "-o", str(binary)])
        print(run(name + "-run", [str(binary)]).strip() or f"{name} passed")

    source_path = root / "Sources/InnoDI/InnoDI.swift"
    source = source_path.read_text()
    for wrapper, heading in [("Lazy", "/// A deferred reference"),
                             ("Provider", "/// A factory handle")]:
        start = source.index(heading)
        section = source[start:source.index("public struct " + wrapper + "<T>", start)]
        code = section.split("/// ```swift\n", 1)[1].split("/// ```", 1)[0]
        # Extract the authored code without changing any binding or type name.
        code = "\n".join(line.removeprefix("/// ") for line in code.splitlines())
        fixture = root / f"Tests/DeferredDocumentationFixtures/{wrapper}.swift.fixture"
        template = fixture.read_text()
        marker = "// INNODI_DOCUMENTED_EXAMPLE"
        if template.count(marker) != 1:
            raise RuntimeError(f"Expected one example insertion marker in {fixture}")
        execute(wrapper + "Documentation", template.replace(marker, code), library=True)

    for readme in ["README.md", "README.ko.md"]:
        text = (root / readme).read_text()
        snippets = re.findall(r"<!-- innodi:compile -->\s*```swift\n(.*?)\n```", text, re.DOTALL)
        if len(snippets) < 2:
            raise RuntimeError(f"Missing initial marked examples in {readme}")
        for index, snippet in enumerate(snippets[:2], 1):
            execute(readme.replace(".", "_") + str(index), snippet + "\n")

    manifest = {"commands": rows,
                "plugin_sha256": hashlib.sha256(plugin.read_bytes()).hexdigest(),
                "public_source_sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
                "scope": "Two exact public deferred examples and two initial marked examples per README"}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
