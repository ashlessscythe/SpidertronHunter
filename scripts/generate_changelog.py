#!/usr/bin/env python3
"""Convert Keep-a-Changelog CHANGELOG.md into Factorio changelog.txt."""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

SEPARATOR = "-" * 99

# Keep-a-Changelog → Factorio category names (official-ish set)
CATEGORY_MAP = {
    "added": "Features",
    "fixed": "Bugfixes",
    "changed": "Changes",
    "removed": "Changes",
    "deprecated": "Changes",
    "security": "Bugfixes",
    "major features": "Major Features",
    "features": "Features",
    "bugfixes": "Bugfixes",
    "changes": "Changes",
}

# This regular expression matches version header lines in a Keep-a-Changelog style Markdown file.
# It looks for lines that start with '##', followed by a version in square brackets (e.g., [1.2.3]), 
# and optionally a date after a dash (e.g., — 2024-05-12).
# The named groups 'version' and 'date' can be accessed from the match.
VERSION_RE = re.compile(
    r"^##\s+\[(?P<version>[^\]]+)\](?:\s*[—–-]\s*(?P<date>\d{4}-\d{2}-\d{2}))?\s*$"
)
CATEGORY_RE = re.compile(r"^###\s+(?P<name>.+?)\s*$")
BULLET_RE = re.compile(r"^-\s+(?P<text>.+)$")
MD_BOLD_RE = re.compile(r"\*\*(.+?)\*\*")
MD_CODE_RE = re.compile(r"`([^`]+)`")
MD_LINK_RE = re.compile(r"\[([^\]]+)\]\([^)]+\)")


def strip_markdown(text: str) -> str:
    text = MD_LINK_RE.sub(r"\1", text)
    text = MD_BOLD_RE.sub(r"\1", text)
    text = MD_CODE_RE.sub(r"\1", text)
    return text.strip()


def parse_changelog(md: str) -> list[dict]:
    versions: list[dict] = []
    current: dict | None = None
    category: str | None = None

    for raw in md.splitlines():
        line = raw.rstrip()
        if not line or line.startswith("# "):
            continue

        vm = VERSION_RE.match(line)
        if vm:
            version = vm.group("version").strip()
            # Skip unversioned catch-all sections like "Earlier"
            if not re.match(r"^\d+\.\d+", version):
                current = None
                category = None
                continue
            current = {
                "version": version,
                "date": (vm.group("date") or "").strip() or None,
                "categories": {},  # name -> [entries]
                "order": [],
            }
            versions.append(current)
            category = None
            continue

        if current is None:
            continue

        cm = CATEGORY_RE.match(line)
        if cm:
            key = cm.group("name").strip().lower()
            category = CATEGORY_MAP.get(key)
            if category is None:
                # Preserve unknown ### headings as Factorio categories
                category = cm.group("name").strip()
            if category not in current["categories"]:
                current["categories"][category] = []
                current["order"].append(category)
            continue

        bm = BULLET_RE.match(line)
        if bm and category:
            entry = strip_markdown(bm.group("text"))
            if entry:
                current["categories"][category].append(entry)
            continue

    return versions


def render(versions: list[dict]) -> str:
    blocks: list[str] = []
    for ver in versions:
        cats = [
            (name, ver["categories"][name])
            for name in ver["order"]
            if ver["categories"].get(name)
        ]
        if not cats:
            continue

        lines = [SEPARATOR, f"Version: {ver['version']}"]
        if ver["date"]:
            lines.append(f"Date: {ver['date']}")
        lines.append("")
        for i, (name, entries) in enumerate(cats):
            if i:
                lines.append("")
            lines.append(f"  {name}:")
            for entry in entries:
                lines.append(f"    - {entry}")
        blocks.append("\n".join(lines))

    if not blocks:
        raise SystemExit("No version sections found in CHANGELOG.md")

    return "\n\n".join(blocks) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "-i",
        "--input",
        type=Path,
        default=Path("CHANGELOG.md"),
        help="Source Keep-a-Changelog markdown (default: CHANGELOG.md)",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("changelog.txt"),
        help="Factorio changelog.txt destination (default: changelog.txt)",
    )
    args = parser.parse_args()

    if not args.input.is_file():
        print(f"error: missing {args.input}", file=sys.stderr)
        return 1

    text = render(parse_changelog(args.input.read_text(encoding="utf-8")))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(text.encode("utf-8"))
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
