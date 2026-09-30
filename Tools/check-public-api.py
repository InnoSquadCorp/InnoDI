#!/usr/bin/env python3
"""Validate the compiler-emitted public API against a checked-in baseline."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 11
PUBLIC_PRODUCT_MODULES = ("InnoDI", "InnoDISwiftUI", "InnoDITesting")
VOLATILE_SYMBOL_KEYS = {
    "declarationFragments",
    "declaration",
    "docComment",
    "functionSignature",
    "location",
    "names",
}
VOLATILE_RELATIONSHIP_KEYS = {"sourceOrigin", "targetFallback"}
IMPLICIT_GENERIC_CONSTRAINTS = {"s:s8CopyableP", "s:s9EscapableP"}
# Swift 6.4 also reports the implicit Copyable and Escapable conformances of a
# constrained extension's conformance, such as the one @Observable writes. As
# with generic constraints above, the gate does not record those requirements.
TOOLCHAIN_SYNTHESIZED_RELATIONSHIP_TARGETS = {"s:s16SendableMetatypeP"} | IMPLICIT_GENERIC_CONSTRAINTS


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare InnoDI product symbol graphs with the public API baseline."
    )
    parser.add_argument(
        "--update",
        action="store_true",
        help="Replace the baseline after an intentional, reviewed public API change.",
    )
    parser.add_argument(
        "--baseline",
        type=Path,
        help="Override the default Tools/public-api-baseline.json path.",
    )
    return parser.parse_args()


def dump_symbol_graphs(package_root: Path) -> Path:
    command = [
        "swift",
        "package",
        "dump-symbol-graph",
        "--minimum-access-level",
        "public",
        "--skip-synthesized-members",
        "--skip-inherited-docs",
    ]
    result = subprocess.run(
        command,
        cwd=package_root,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    sys.stdout.write(result.stdout)
    if result.returncode != 0:
        raise SystemExit(result.returncode)

    matches = re.findall(r"^Files written to (.+)$", result.stdout, re.MULTILINE)
    if not matches:
        raise SystemExit("Unable to locate the SwiftPM symbol-graph output directory.")

    output_directory = Path(matches[-1]).resolve()
    if not output_directory.is_dir():
        raise SystemExit(f"Symbol-graph output directory does not exist: {output_directory}")
    return output_directory


def normalize_symbol(symbol: dict[str, Any], alias_rhs: list[str] | None = None) -> dict[str, Any]:
    normalized = {
        key: value
        for key, value in symbol.items()
        if key not in VOLATILE_SYMBOL_KEYS
    }
    normalized["kind"] = {"identifier": symbol["kind"]["identifier"]}
    normalized["identifier"] = {
        "precise": symbol["identifier"]["precise"],
        "interfaceLanguage": symbol["identifier"]["interfaceLanguage"],
    }
    normalized["declarationContract"] = declaration_contract(symbol, alias_rhs)
    # Older symbol-graph emitters omit functionSignature for macros, including
    # parameterless ones. Their declaration fragments still carry defaults.
    if "functionSignature" in symbol or symbol["kind"]["identifier"] == "swift.macro":
        normalized["parameterDefaults"] = parameter_defaults(symbol)
    if "swiftGenerics" in normalized:
        normalized["swiftGenerics"] = normalize_generic_context(
            normalized["swiftGenerics"]
        )
    if "swiftExtension" in normalized:
        normalized["swiftExtension"] = normalize_generic_context(
            normalized["swiftExtension"]
        )
    return normalized


def declaration_contract(symbol: dict[str, Any], alias_rhs: list[str] | None = None) -> dict[str, Any]:
    """Retain actor isolation, accessor capability, and self-mutation semantics.

    Compiler declaration fragments carry facts missing from USRs and method
    signatures. Keep their semantic tokens, not toolchain-rendered full text.
    Inferred actor attributes are emitted on members as well as their owner.
    """
    fragments = symbol.get("declarationFragments")
    if not isinstance(fragments, list) or not fragments:
        raise ValueError("Missing declaration fragments for " + symbol["identifier"]["precise"])
    declaration_keywords = {"func", "init", "deinit", "var", "let", "subscript", "class",
                            "struct", "enum", "actor", "protocol", "typealias", "associatedtype",
                            "case", "macro", "operator", "precedencegroup"}
    prefix = []
    for fragment in fragments:
        if fragment["kind"] == "keyword" and fragment["spelling"] in declaration_keywords:
            break
        prefix.append(fragment)
    for index, fragment in enumerate(prefix):
        if fragment["kind"] == "attribute" and fragment["spelling"] == "@":
            following = next((part for part in prefix[index + 1:] if part["spelling"].strip()), None)
            if following is None or "preciseIdentifier" not in following:
                raise ValueError("Missing named-attribute identity for " + symbol["identifier"]["precise"])
    # A referenced type in an attribute is a stable identity (including custom
    # global actors). Plain attributes like availability have dedicated graph
    # records and are deliberately not compared as rendered text.
    attributes = sorted({fragment["preciseIdentifier"] for fragment in prefix
                         if fragment["kind"] == "attribute" and "preciseIdentifier" in fragment})
    prefix_text = "".join(fragment["spelling"] for fragment in prefix)
    isolation = re.findall(r"\bnonisolated(?:\s*\(\s*(?:unsafe|nonsending)\s*\))?|\bisolated\b|@concurrent\b", prefix_text)
    contract: dict[str, Any] = {
        "namedAttributes": attributes,
        "isolationModifiers": sorted({re.sub(r"\s+", "", value) for value in isolation}),
    }
    kind = symbol["kind"]["identifier"]
    if kind == "swift.typealias":
        tokens = typealias_contract(symbol)
        if alias_rhs is None:
            raise ValueError("Missing compiler-interface alias for " + symbol["identifier"]["precise"])
        # Swift 6.2 symbol graphs omit @Sendable, even though consumers enforce
        # it. Keep that effect from the serialized module's compiler interface
        # on every toolchain, never from source spelling or the old baseline.
        contract["aliasedType"] = [token for index, token in enumerate(tokens)
                                   if not (token == "@" and tokens[index + 1:index + 2] == ["Sendable"])
                                   and not (token == "Sendable" and index > 0 and tokens[index - 1] == "@")]
        contract["aliasedSendablePositions"] = alias_sendable_positions(alias_rhs)
    if kind == "swift.method":
        contract["mutating"] = bool(re.search(r"\bmutating\b", prefix_text))
    if kind in {"swift.property", "swift.type.property", "swift.subscript", "swift.type.subscript"}:
        text = "".join(fragment["spelling"] for fragment in fragments)
        keywords = {fragment["spelling"] for fragment in fragments if fragment["kind"] == "keyword"}
        accessors = re.search(r"\{([^{}]*)\}\s*$", text)
        if accessors:
            body = accessors.group(1)
            if not re.search(r"\bget\b", body):
                raise ValueError("Unknown accessor contract for " + symbol["identifier"]["precise"])
            contract["writable"] = bool(re.search(r"\bset\b", body))
            contract["mutatingGetter"] = bool(re.search(r"\bmutating\s+get\b", body))
            contract["nonmutatingSetter"] = bool(re.search(r"\bnonmutating\s+set\b", body))
        elif "let" in keywords:
            contract["writable"] = False
            contract["mutatingGetter"] = False
            contract["nonmutatingSetter"] = False
        elif "var" in keywords:
            contract["writable"] = True
            contract["mutatingGetter"] = False
            contract["nonmutatingSetter"] = False
        else:
            raise ValueError("Missing accessor contract for " + symbol["identifier"]["precise"])
    return contract


def interface_tokens(text: str) -> list[str]:
    """Lex compiler interface declarations, shielding comments and literals.

    This is not a source-level type inference fallback. Only the interface
    emitted from the already-built module is accepted by the caller.
    """
    def comment_end(start: int) -> int:
        if text.startswith("//", start):
            end = text.find("\n", start)
            return len(text) if end < 0 else end
        depth, cursor = 1, start + 2
        while cursor < len(text) and depth:
            if text.startswith("/*", cursor):
                depth += 1
                cursor += 2
            elif text.startswith("*/", cursor):
                depth -= 1
                cursor += 2
            else:
                cursor += 1
        if depth:
            raise ValueError("Unterminated compiler-interface comment")
        return cursor

    def string_end(start: int) -> int | None:
        match = re.match(r'(#+)?("""|")', text[start:])
        if not match:
            return None
        hashes, quotes = match.group(1) or "", match.group(2)
        cursor = start + len(match.group())
        while cursor < len(text):
            if text.startswith(quotes + hashes, cursor):
                return cursor + len(quotes) + len(hashes)
            if text.startswith("\\" + hashes, cursor):
                cursor += 1 + len(hashes)
                if text[cursor:cursor + 1] == "(":
                    depth, cursor = 1, cursor + 1
                    while cursor < len(text) and depth:
                        if text.startswith(("//", "/*"), cursor):
                            cursor = comment_end(cursor)
                        elif (end := string_end(cursor)) is not None:
                            cursor = end
                        else:
                            depth += (text[cursor] == "(") - (text[cursor] == ")")
                            cursor += 1
                    if depth:
                        raise ValueError("Unterminated compiler-interface interpolation")
                else:
                    cursor += 1
            else:
                cursor += 1
        raise ValueError("Unterminated compiler-interface string")

    tokens, cursor = [], 0
    while cursor < len(text):
        if text.startswith(("//", "/*"), cursor):
            cursor = comment_end(cursor)
        elif (end := string_end(cursor)) is not None:
            tokens.append("<literal>")
            cursor = end
        elif text[cursor] == "\n":
            tokens.append("\n")
            cursor += 1
        elif text[cursor].isspace():
            cursor += 1
        else:
            match = re.match(r'`[^`\n]+`|\w+|->|::|==|[^\s]', text[cursor:])
            if not match:
                raise ValueError("Unknown compiler-interface token")
            tokens.append(match.group())
            cursor += len(match.group())
    return tokens


def interface_aliases(text: str, module: str) -> dict[tuple[str, ...], list[str]]:
    """Index aliases by nominal scope, not ambiguous leaf names or line numbers."""
    tokens = interface_tokens(text)
    aliases: dict[tuple[str, ...], list[str]] = {}
    scopes: list[tuple[str, ...] | None] = []
    modules = {module}
    pending, index = None, 0
    identifier = lambda token: bool(re.fullmatch(r'`[^`]+`|\w+', token))
    while index < len(tokens):
        token = tokens[index]
        if token == "import" and index + 1 < len(tokens) and identifier(tokens[index + 1]):
            modules.add(tokens[index + 1].strip("`"))
        elif token in {"struct", "class", "enum", "actor", "protocol", "extension"}:
            cursor = index + 1
            if cursor < len(tokens) and identifier(tokens[cursor]) and tokens[cursor] not in {"func", "var", "subscript"}:
                names = [tokens[cursor].strip("`")]
                cursor += 1
                while cursor + 1 < len(tokens) and tokens[cursor] in {".", "::"} and identifier(tokens[cursor + 1]):
                    names.append(tokens[cursor + 1].strip("`"))
                    cursor += 2
                if len(names) > 1 and names[0] in modules:
                    names.pop(0)
                pending = tuple(names)
        elif token in {"func", "init", "deinit", "var", "subscript"}:
            pending = None
        elif token == "{":
            scopes.append(pending)
            pending = None
        elif token == "}":
            if not scopes:
                raise ValueError("Unbalanced compiler-interface scope")
            scopes.pop()
            pending = None
        elif token == "typealias" and all(scope is not None for scope in scopes):
            if index + 1 >= len(tokens) or not identifier(tokens[index + 1]):
                raise ValueError("Missing compiler-interface alias name")
            name, cursor = tokens[index + 1].strip("`"), index + 2
            while cursor < len(tokens) and tokens[cursor] not in {"=", "\n", "{", "}"}:
                cursor += 1
            if cursor == len(tokens) or tokens[cursor] != "=":
                raise ValueError("Missing compiler-interface alias assignment")
            end = cursor + 1
            while end < len(tokens) and tokens[end] not in {"\n", "{", "}"}:
                end += 1
            rhs = tokens[cursor + 1:end]
            if not rhs or (end < len(tokens) and tokens[end] != "\n"):
                raise ValueError("Incomplete compiler-interface alias RHS")
            path = tuple(part for scope in scopes for part in scope) + (name,)
            if path in aliases and aliases[path] != rhs:
                raise ValueError("Ambiguous compiler-interface alias: " + ".".join(path))
            aliases[path] = rhs
            index = end
        index += 1
    if scopes:
        raise ValueError("Unclosed compiler-interface scope")
    return aliases


def alias_sendable_positions(tokens: list[str]) -> list[int]:
    """Locate each function's @Sendable without toolchain-rendered type names.

    Structural punctuation distinguishes outer, parameter, return and tuple
    function types. Other attributes do not shift these locations; their
    identities/effects remain in the symbol-graph RHS contract.
    """
    positions, position, index = [], 0, 0
    while index < len(tokens):
        token = tokens[index]
        if token == "@":
            index += 1
            if index == len(tokens):
                raise ValueError("Incomplete compiler-interface type attribute")
            if tokens[index] == "Sendable":
                positions.append(position)
            index += 1
            while index + 1 < len(tokens) and tokens[index] in {".", "::"}:
                index += 2
            if index < len(tokens) and tokens[index] == "(" and tokens[index - 1] == "convention":
                while index < len(tokens) and tokens[index] != ")":
                    index += 1
                if index == len(tokens):
                    raise ValueError("Unclosed compiler-interface convention")
                index += 1
            continue
        if token in {"(", ")", "[", "]", "<", ">", ",", ":", "->", "?", "!", "&"}:
            position += 1
        index += 1
    return positions


def compiler_alias_interfaces(module_directory: Path, module: str) -> dict[tuple[str, ...], list[str]]:
    info = json.loads(subprocess.check_output(["swiftc", "-print-target-info"], text=True))
    arch = info["target"]["arch"]
    candidates = []
    for directory in (module_directory, module_directory / "Modules"):
        path = directory / (module + ".swiftmodule")
        candidates.extend([path] if path.is_file() else sorted(path.glob(arch + "-*.swiftmodule")))
    candidates = sorted({path.resolve() for path in candidates})
    if len(candidates) != 1:
        raise ValueError(f"Expected one built module for {module}, found {candidates}")
    frontend = shutil.which("swift-frontend") or subprocess.check_output(
        ["xcrun", "--find", "swift-frontend"], text=True).strip()
    sdk = os.environ.get("SDKROOT") or subprocess.check_output(
        ["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    with tempfile.TemporaryDirectory(prefix="innodi-api-interface-") as temporary:
        folder = Path(temporary)
        interface = folder / (module + ".swiftinterface")
        result = subprocess.run([
            frontend, "-merge-modules", "-emit-module", "-emit-module-path", str(folder / (module + ".swiftmodule")),
            "-emit-module-interface-path", str(interface), "-module-name", module, str(candidates[0]),
            "-enable-library-evolution", "-swift-version", "6", "-target", info["target"]["triple"], "-sdk", sdk,
            "-I", str(module_directory), "-I", str(module_directory / "Modules"),
        ], capture_output=True, text=True)
        if result.returncode or not interface.is_file():
            raise ValueError(f"Cannot export compiler interface for {module}: {result.stderr}")
        return interface_aliases(interface.read_text(encoding="utf-8"), module)


def generic_parameter_slots(symbol: dict[str, Any]) -> dict[str, str]:
    """Resolve compiler-declared parameters without inventing missing type USRs."""
    parameters = symbol.get("swiftGenerics", {}).get("parameters", [])
    if not isinstance(parameters, list):
        raise ValueError("Invalid generic parameters for " + symbol["identifier"]["precise"])
    names: dict[str, str] = {}
    slots: set[tuple[int, int]] = set()
    for parameter in parameters:
        if not isinstance(parameter, dict):
            raise ValueError("Invalid generic parameter for " + symbol["identifier"]["precise"])
        name, depth, index = (parameter.get(key) for key in ("name", "depth", "index"))
        if (not isinstance(name, str) or not name or type(depth) is not int or type(index) is not int
                or depth < 0 or index < 0 or name in names or (depth, index) in slots):
            raise ValueError("Ambiguous generic parameter for " + symbol["identifier"]["precise"])
        names[name] = f"generic:{depth}:{index}"
        slots.add((depth, index))
    return names


def typealias_contract(symbol: dict[str, Any]) -> list[str]:
    """Keep RHS structure/effects and referenced identities, not rendered names.

    An alias USR identifies only its declaration, not its underlying type.
    Tokenize punctuation and keywords independently of fragment/space layout;
    use compiler identities for nominal types and actors, depth/index slots for
    generic parameters. Serialized-module extraction omits parameter USRs that
    direct symbol-graph emission includes, but retains swiftGenerics metadata.
    """
    fragments = symbol["declarationFragments"]
    rhs = None
    for index, fragment in enumerate(fragments):
        if fragment["kind"] != "text":
            continue
        assignment = re.search(r"(?<![=<>!])=(?!=)", fragment["spelling"])
        if assignment:
            rhs = [{"kind": "text", "spelling": fragment["spelling"][assignment.end():]},
                   *fragments[index + 1:]]
            break
    if not rhs or not any(part["spelling"].strip() for part in rhs):
        raise ValueError("Missing typealias RHS for " + symbol["identifier"]["precise"])
    parameters = generic_parameter_slots(symbol)
    tokens = []
    for index, fragment in enumerate(rhs):
        spelling = fragment["spelling"]
        identity = fragment.get("preciseIdentifier")
        if fragment["kind"] == "typeIdentifier" and (not identity or identity.endswith("mfp")):
            # Never infer a nominal type from its spelling, or mistake a
            # qualified nominal name for a same-spelled generic parameter.
            if spelling not in parameters or (tokens and tokens[-1] == "."):
                raise ValueError("Missing aliased-type identity for " + symbol["identifier"]["precise"])
            tokens.append(parameters[spelling])
            continue
        if fragment["kind"] == "attribute" and spelling == "@":
            following = next((part for part in rhs[index + 1:] if part["spelling"].strip()), None)
            if following is None or not following.get("preciseIdentifier"):
                raise ValueError("Missing aliased-actor identity for " + symbol["identifier"]["precise"])
        if identity:
            # Module qualifications (for example Swift.Int) are rendered as
            # plain text before the identity-bearing type fragment. The USR
            # already contains that qualification. Do not drop referenced
            # enclosing types or their generic arguments.
            while len(tokens) >= 2 and tokens[-1] == "." and re.fullmatch(r"\w+", tokens[-2]):
                del tokens[-2:]
            tokens.append("reference:" + identity)
        else:
            tokens.extend(re.findall(r"[\w]+|->|[^\s\w]", spelling))
    return tokens


def parameter_defaults(symbol: dict[str, Any]) -> list[bool]:
    """Keep call-site optionality, not toolchain-rendered declaration text.

    Swift's parameter signature omits defaults, but its full declaration marks
    each external parameter and includes the default assignment in text fragments.
    Types cannot contain a single assignment; generic same-type constraints use
    ==. Default expressions (including closures/strings with commas or equals)
    need not be parsed or retained to detect removal of a default.
    """
    signature = symbol.get("functionSignature")
    parameters = signature.get("parameters", []) if signature is not None else None
    fragments = symbol.get("declarationFragments")
    if not isinstance(fragments, list) or not fragments:
        raise ValueError("Missing declaration fragments for " + symbol["identifier"]["precise"])
    groups: list[list[str]] = []
    previous_kind = None
    for fragment in fragments:
        # Subscripts without external labels emit only internalParam. A named
        # argument's internalParam immediately follows its externalParam and
        # belongs to the same group.
        if fragment["kind"] == "externalParam" or (
            fragment["kind"] == "internalParam" and previous_kind != "externalParam"
        ):
            groups.append([])
        elif groups and fragment["kind"] == "text":
            groups[-1].append(fragment["spelling"])
        if fragment["spelling"].strip():
            previous_kind = fragment["kind"]
    if parameters is not None and len(groups) != len(parameters):
        raise ValueError(
            "Cannot recover default-argument contract for "
            + symbol["identifier"]["precise"]
            + ": " + repr(symbol.get("declarationFragments"))
        )
    return [bool(re.search(r"(?<![=<>!])=(?!=)", "".join(group))) for group in groups]


def normalize_generic_context(context: dict[str, Any]) -> dict[str, Any]:
    normalized = dict(context)
    constraints = normalized.get("constraints")
    if isinstance(constraints, list):
        normalized["constraints"] = [
            constraint
            for constraint in constraints
            if constraint.get("rhsPrecise") not in IMPLICIT_GENERIC_CONSTRAINTS
        ]
    return normalized


def product_graph_paths(output_directory: Path, module: str) -> list[Path]:
    primary = output_directory / f"{module}.symbols.json"
    if not primary.is_file():
        raise SystemExit(f"Missing public product symbol graph: {primary.name}")
    return [primary, *sorted(output_directory.glob(f"{module}@*.symbols.json"))]


def is_product_declaration(symbol: dict[str, Any], module: str) -> bool:
    location = symbol.get("location", {}).get("uri", "")
    return f"/Sources/{module}/" in location


def normalize_relationship(relationship: dict[str, Any]) -> dict[str, Any]:
    normalized = {
        key: value
        for key, value in relationship.items()
        if key not in VOLATILE_RELATIONSHIP_KEYS
    }
    if "swiftConstraints" in normalized:
        constraints = [
            constraint
            for constraint in normalized["swiftConstraints"]
            if constraint.get("rhsPrecise") not in IMPLICIT_GENERIC_CONSTRAINTS
        ]
        if constraints:
            normalized["swiftConstraints"] = constraints
        else:
            normalized.pop("swiftConstraints")
    return normalized


def normalize_product_graph(output_directory: Path, module: str, module_directory: Path | None = None) -> dict[str, Any]:
    payloads = [
        json.loads(path.read_text(encoding="utf-8"))
        for path in product_graph_paths(output_directory, module)
    ]
    symbols_by_identifier: dict[str, dict[str, Any]] = {}
    extension_blocks: set[str] = set()
    aliases = None
    for payload in payloads:
        symbol_payload = payload.get("symbols", [])
        if isinstance(symbol_payload, dict):
            symbol_payload = symbol_payload.values()
        for symbol in symbol_payload:
            # SwiftPM on Swift 6.4 emits extension block symbols for
            # extensions of external types even with
            # --omit-extension-block-symbols, while Swift 6.3 follows that
            # documented default and attaches the members to the extended
            # type. The members carry the API, so fold each block into it.
            if symbol["kind"]["identifier"] == "swift.extension":
                extension_blocks.add(symbol["identifier"]["precise"])
                continue
            if not is_product_declaration(symbol, module):
                continue
            alias_rhs = None
            if symbol["kind"]["identifier"] == "swift.typealias":
                if aliases is None:
                    aliases = compiler_alias_interfaces(module_directory or output_directory, module)
                alias_rhs = aliases.get(tuple(symbol["pathComponents"]))
            normalized = normalize_symbol(symbol, alias_rhs)
            symbols_by_identifier[normalized["identifier"]["precise"]] = normalized

    if not symbols_by_identifier:
        raise SystemExit(f"No source-authored public symbols found for {module}.")

    extended_types = {
        relationship["source"]: relationship["target"]
        for payload in payloads
        for relationship in payload.get("relationships", [])
        if relationship.get("kind") == "extensionTo"
        and relationship.get("source") in extension_blocks
    }

    symbol_identifiers = set(symbols_by_identifier)
    relationships_by_identity: dict[str, dict[str, Any]] = {}
    for payload in payloads:
        for relationship in payload.get("relationships", []):
            # A block's own relationships (extensionTo, and conformances that
            # the omitted form reports on the external type) are not
            # sourced from a product symbol.
            if relationship.get("source") not in symbol_identifiers:
                continue
            if relationship.get("target") in TOOLCHAIN_SYNTHESIZED_RELATIONSHIP_TARGETS:
                continue
            normalized = normalize_relationship(relationship)
            target = normalized.get("target", "")
            if target in extension_blocks or target.startswith("s:e:"):
                if target not in extended_types:
                    raise SystemExit(f"Extension block without an extended type: {target}")
                normalized["target"] = extended_types[target]
            identity = json.dumps(normalized, sort_keys=True, separators=(",", ":"))
            relationships_by_identity[identity] = normalized

    symbols = sorted(
        symbols_by_identifier.values(),
        key=lambda symbol: symbol["identifier"]["precise"],
    )
    relationships = [
        relationships_by_identity[identity]
        for identity in sorted(relationships_by_identity)
    ]
    return {
        "file": f"{module}.symbols.json",
        "module": module,
        "symbols": symbols,
        "relationships": relationships,
    }


def current_contract(output_directory: Path) -> dict[str, Any]:
    module_directory = Path(subprocess.check_output(["swift", "build", "--show-bin-path"], text=True).strip())
    return {
        "schemaVersion": SCHEMA_VERSION,
        "graphs": [
            normalize_product_graph(output_directory, module, module_directory)
            for module in PUBLIC_PRODUCT_MODULES
        ],
    }


def encoded(contract: dict[str, Any]) -> str:
    return json.dumps(contract, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def summarize_difference(baseline: dict[str, Any], current: dict[str, Any]) -> None:
    baseline_graphs = {graph["file"]: graph for graph in baseline.get("graphs", [])}
    current_graphs = {graph["file"]: graph for graph in current.get("graphs", [])}

    for graph_name in sorted(baseline_graphs.keys() | current_graphs.keys()):
        old_graph = baseline_graphs.get(graph_name, {"symbols": [], "relationships": []})
        new_graph = current_graphs.get(graph_name, {"symbols": [], "relationships": []})
        old_symbols = {
            symbol["identifier"]["precise"]: symbol for symbol in old_graph["symbols"]
        }
        new_symbols = {
            symbol["identifier"]["precise"]: symbol for symbol in new_graph["symbols"]
        }

        added = sorted(new_symbols.keys() - old_symbols.keys())
        removed = sorted(old_symbols.keys() - new_symbols.keys())
        changed = sorted(
            identifier
            for identifier in old_symbols.keys() & new_symbols.keys()
            if old_symbols[identifier] != new_symbols[identifier]
        )
        if added or removed or changed:
            print(f"[{graph_name}]", file=sys.stderr)
            for label, identifiers in (
                ("added", added),
                ("removed", removed),
                ("changed", changed),
            ):
                for identifier in identifiers:
                    print(f"  {label}: {identifier}", file=sys.stderr)
                    if label == "changed":
                        old, new = old_symbols[identifier], new_symbols[identifier]
                        for key in sorted(old.keys() | new.keys()):
                            if old.get(key) != new.get(key):
                                print(f"    {key}: {old.get(key)!r} -> {new.get(key)!r}", file=sys.stderr)

        if old_graph["relationships"] != new_graph["relationships"]:
            print(f"[{graph_name}] relationships changed", file=sys.stderr)
            old_relationships = {json.dumps(r, sort_keys=True) for r in old_graph["relationships"]}
            new_relationships = {json.dumps(r, sort_keys=True) for r in new_graph["relationships"]}
            for label, identities in (
                ("added", new_relationships - old_relationships),
                ("removed", old_relationships - new_relationships),
            ):
                for identity in sorted(identities):
                    print(f"  {label} relationship: {identity}", file=sys.stderr)


def main() -> int:
    arguments = parse_arguments()
    package_root = Path(__file__).resolve().parent.parent
    baseline_path = (
        arguments.baseline.resolve()
        if arguments.baseline
        else package_root / "Tools" / "public-api-baseline.json"
    )

    output_directory = dump_symbol_graphs(package_root)
    current = current_contract(output_directory)

    if arguments.update:
        baseline_path.write_text(encoded(current), encoding="utf-8")
        print(f"Updated public API baseline: {baseline_path}")
        return 0

    if not baseline_path.is_file():
        print(
            f"Public API baseline is missing: {baseline_path}\n"
            "Run Tools/check-public-api.py --update after reviewing the intended API.",
            file=sys.stderr,
        )
        return 1

    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    if baseline == current:
        symbol_count = sum(len(graph["symbols"]) for graph in current["graphs"])
        print(
            f"Public API baseline: OK ({symbol_count} symbols across "
            f"{len(current['graphs'])} graphs)"
        )
        return 0

    print("Public API differs from Tools/public-api-baseline.json.", file=sys.stderr)
    summarize_difference(baseline, current)
    print(
        "Review the SemVer impact, then run Tools/check-public-api.py --update "
        "only when the change is intentional.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
