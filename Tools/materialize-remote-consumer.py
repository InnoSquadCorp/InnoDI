#!/usr/bin/env python3
"""Materialize the exact-SHA smoke consumer, including renamed public forks."""
import argparse
import json
from pathlib import Path
import re
import sys


def identity(url):
    match = re.fullmatch(r"https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)\.git", url)
    if not match or match[1] in (".", "..") or match[2] in (".", ".."):
        raise ValueError("consumer URL must be an exact public GitHub HTTPS clone URL")
    return match[2].lower()


def materialize(fixtures, output, url, revision):
    package_identity = identity(url)
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("consumer revision must be an exact lowercase SHA")
    paths = sorted(fixtures.rglob("*.fixture"))
    if not paths:
        raise ValueError("missing smoke fixtures")
    for source in paths:
        destination = output / source.relative_to(fixtures).with_suffix("")
        text = source.read_text().replace("{{INNODI_REVISION}}", revision)
        if destination.name == "Package.swift":
            original = json.dumps("https://github.com/InnoSquadCorp/InnoDI.git")
            if text.count(original) != 1:
                raise ValueError("smoke manifest must declare exactly one canonical dependency")
            text = text.replace(original, json.dumps(url))
            text = text.replace('package: "InnoDI"', 'package: ' + json.dumps(package_identity))
        if re.search(r"\{\{INNODI_[A-Z_]+\}\}", text):
            raise ValueError("unresolved smoke fixture placeholder")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(text)
    return package_identity


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures", type=Path, default=Path("Tests/RemoteConsumerSmoke"))
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--repository-url", required=True)
    parser.add_argument("--revision", required=True)
    args = parser.parse_args()
    try:
        print(materialize(args.fixtures, args.output, args.repository_url, args.revision))
    except (ValueError, OSError) as error:
        print(f"Consumer materialization rejected: {error}", file=sys.stderr)
        sys.exit(1)
