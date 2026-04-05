#!/usr/bin/env python3
"""Generate deterministic repository facts from the live tree.

This script owns the generated structural inventory for the repo. It should be
the only supported source for exact package, tree, and MCP surface counts.
"""

from __future__ import annotations

import argparse
import difflib
import re
import sys
from pathlib import Path
from typing import Iterable, List, Sequence, Tuple

REPO_ROOT = Path(__file__).resolve().parent.parent
PACKAGE_SWIFT = REPO_ROOT / "Package.swift"
MCP_TOOLS = REPO_ROOT / "Sources/OracleOS/MCP/MCPTools.swift"
OUTPUT_PATH = REPO_ROOT / "docs/REPO_FACTS.md"
PYTHON_ROOTS = [REPO_ROOT / "scripts", REPO_ROOT / "vision-sidecar"]


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def count_swift_files(root: Path) -> int:
    return sum(1 for _ in root.rglob("*.swift"))


def iter_repo_python_files() -> Iterable[Path]:
    for root in PYTHON_ROOTS:
        if not root.exists():
            continue
        for path in root.rglob("*.py"):
            if "__pycache__" in path.parts:
                continue
            yield path


def parse_products(package_source: str) -> List[Tuple[str, str]]:
    matches = re.findall(
        r"\.\s*(library|executable)\s*\(\s*name:\s*\"([^\"]+)\"",
        package_source,
    )
    return [(name, kind) for kind, name in matches]


def parse_targets(package_source: str) -> List[Tuple[str, str]]:
    matches = re.findall(
        (
            r"\.\s*(target|executableTarget|testTarget)"
            r"\s*\(\s*name:\s*\"([^\"]+)\""
        ),
        package_source,
    )
    return [(name, kind) for kind, name in matches]


def parse_package_name(package_source: str) -> str:
    match = re.search(r'name:\s*\"([^\"]+)\"', package_source)
    if not match:
        raise ValueError("Could not parse package name from Package.swift")
    return match.group(1)


def parse_platform_target(package_source: str) -> str:
    match = re.search(r"\.macOS\(\.v(\d+)\)", package_source)
    if not match:
        raise ValueError("Could not parse macOS target from Package.swift")
    return f"macOS {match.group(1)}+"


def parse_tool_categories(mcp_tools_source: str) -> List[Tuple[str, int]]:
    categories: List[Tuple[str, int]] = []
    current_name: str | None = None
    current_expected: int | None = None
    current_count = 0

    for line in mcp_tools_source.splitlines():
        header = re.match(r"\s*// MARK: - (.+?) Tool[s]? \((\d+)\)", line)
        if header:
            if current_name is not None:
                if current_expected != current_count:
                    raise ValueError(
                        "MCP category "
                        f"'{current_name}' expected {current_expected} "
                        f"tools but found {current_count}"
                    )
                categories.append((current_name, current_count))
            current_name = header.group(1)
            current_expected = int(header.group(2))
            current_count = 0
            continue

        if current_name is not None and line.strip().startswith("tool("):
            current_count += 1

    if current_name is not None:
        if current_expected != current_count:
            raise ValueError(
                "MCP category "
                f"'{current_name}' expected {current_expected} "
                f"tools but found {current_count}"
            )
        categories.append((current_name, current_count))

    if not categories:
        raise ValueError("No MCP categories found in MCPTools.swift")

    return categories


def render_table(
    headers: Sequence[str], rows: Sequence[Sequence[str]]
) -> List[str]:
    table = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join(["---"] * len(headers)) + " |",
    ]
    for row in rows:
        table.append("| " + " | ".join(row) + " |")
    return table


def render_markdown() -> str:
    package_source = read_text(PACKAGE_SWIFT)
    mcp_tools_source = read_text(MCP_TOOLS)

    package_name = parse_package_name(package_source)
    platform_target = parse_platform_target(package_source)
    products = parse_products(package_source)
    targets = parse_targets(package_source)
    tool_categories = parse_tool_categories(mcp_tools_source)

    swift_sources = count_swift_files(REPO_ROOT / "Sources")
    swift_tests = count_swift_files(REPO_ROOT / "Tests")
    python_files = len(list(iter_repo_python_files()))
    total_tools = sum(count for _, count in tool_categories)

    lines: List[str] = [
        "# Repo Facts",
        "",
        (
            "This file is generated from `Package.swift`, "
            "`Sources/OracleOS/MCP/MCPTools.swift`, `Sources/`, `Tests/`, "
            "`scripts/`, and `vision-sidecar/` by "
            "`python3 scripts/generate_repo_facts.py --write`."
        ),
        "Do not edit manually.",
        "",
        "## Package Surface",
        "",
    ]
    lines.extend(
        render_table(
            ["Property", "Value"],
            [
                ["Package name", package_name],
                ["Platform target", platform_target],
                ["Products", str(len(products))],
                ["Targets", str(len(targets))],
            ],
        )
    )
    lines.extend([
        "",
        "### Products",
        "",
    ])
    lines.extend(
        render_table(
            ["Product", "Kind"],
            [[name, kind] for name, kind in products],
        )
    )
    lines.extend([
        "",
        "### Targets",
        "",
    ])
    lines.extend(
        render_table(
            ["Target", "Kind"],
            [[name, kind] for name, kind in targets],
        )
    )
    lines.extend([
        "",
        "## Tree Inventory",
        "",
    ])
    lines.extend(
        render_table(
            ["Property", "Value"],
            [
                ["Swift source files under `Sources/`", str(swift_sources)],
                ["Swift test files under `Tests/`", str(swift_tests)],
                [
                    "Repo-owned Python files under `scripts/` and "
                    "`vision-sidecar/`",
                    str(python_files),
                ],
            ],
        )
    )
    lines.extend([
        "",
        "## MCP Surface",
        "",
        (
            "The tool total is generated from the live `tool(...)` "
            "declarations in `Sources/OracleOS/MCP/MCPTools.swift`. "
            "Section counts are cross-checked against the category headers "
            "in that same file."
        ),
        "",
    ])
    lines.extend(
        render_table(
            ["Category", "Count"],
            [[name, str(count)] for name, count in tool_categories],
        )
    )
    lines.extend([
        "",
        f"Total public tools: {total_tools}",
        "",
    ])
    return "\n".join(lines)


def write_output(content: str) -> None:
    OUTPUT_PATH.write_text(content, encoding="utf-8")


def check_output(content: str) -> int:
    if not OUTPUT_PATH.exists():
        print(f"Missing generated facts file: {OUTPUT_PATH}", file=sys.stderr)
        return 1

    existing = read_text(OUTPUT_PATH)
    if existing == content:
        print(f"Repo facts are current: {OUTPUT_PATH}")
        return 0

    print(f"Repo facts drift detected in {OUTPUT_PATH}", file=sys.stderr)
    diff = difflib.unified_diff(
        existing.splitlines(),
        content.splitlines(),
        fromfile=str(OUTPUT_PATH),
        tofile="generated",
        lineterm="",
    )
    for line in diff:
        print(line, file=sys.stderr)
    return 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate deterministic repo facts from the live tree."
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="Write the generated markdown to docs/REPO_FACTS.md",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if docs/REPO_FACTS.md does not match generated output",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.write and args.check:
        print("Use only one of --write or --check.", file=sys.stderr)
        return 2

    content = render_markdown()

    if args.write:
        write_output(content)
        print(f"Wrote repo facts to {OUTPUT_PATH}")
        return 0

    if args.check:
        return check_output(content)

    print(content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
