#!/usr/bin/env python3
"""mcp_boundary_guard.py — CI enforcement for MCP tool contract completeness.

Checks:
    1. MCPBoundary.swift defines the core MCP boundary types.
    2. MCPDispatch.swift contains the typed dispatch entrypoints.
    3. Every tool declared in MCPTools.swift has a matching MCPToolName
         reference in MCPDispatch*.swift.
    4. No tool name appears more than once in MCPTools.swift.
    5. The advertised product contract remains exactly 30 unique MCP tools.

Exit codes:
    0 — all checks pass
    1 — one or more checks failed (details printed to stderr)
"""
import os
import re
import sys


BOUNDARY_PATH = "Sources/OracleOS/MCP/MCPBoundary.swift"
TOOLS_PATH = "Sources/OracleOS/MCP/MCPTools.swift"
DISPATCH_PATHS = [
    "Sources/OracleOS/MCP/MCPDispatch.swift",
    "Sources/OracleOS/MCP/MCPDispatch+Recipes.swift",
    "Sources/OracleOS/MCP/MCPDispatch+Memory.swift",
    "Sources/OracleOS/MCP/MCPDispatch+Workflow.swift",
    "Sources/OracleOS/MCP/MCPDispatch+Architecture.swift",
]
EXPECTED_TOOL_COUNT = 30


def _read(path: str) -> str:
    if not os.path.exists(path):
        print(f"ERROR: required file not found: {path}", file=sys.stderr)
        sys.exit(1)
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def check_boundary(content: str) -> list[str]:
    errors = []
    required = [
        "enum JSONValue",
        "struct MCPToolRequest",
        "struct MCPToolResponse",
        "enum MCPContent",
    ]
    for token in required:
        if token not in content:
            errors.append(f"MCPBoundary.swift missing: {token}")
    return errors


def check_dispatch_structure(content: str) -> list[str]:
    errors = []
    if "public static func handle(_ request: MCPToolRequest)" not in content:
        errors.append(
            "MCPDispatch.swift missing: public static func handle(_ request: MCPToolRequest)"
        )
    if "private static func dispatch(request: MCPToolRequest)" not in content:
        errors.append(
            "MCPDispatch.swift missing: private static func dispatch(request: MCPToolRequest)"
        )
    if "formatTypedResult" not in content:
        errors.append("MCPDispatch.swift missing: formatTypedResult")
    return errors


def extract_tool_names(tools_content: str) -> list[str]:
    """Return MCPToolName property names declared in MCPTools.swift."""
    return re.findall(r"name:\s*MCPToolName\.(\w+)", tools_content)


def extract_dispatch_tool_references(dispatch_content: str) -> list[str]:
    """Return MCPToolName property names referenced in MCPDispatch*.swift."""
    return re.findall(r"MCPToolName\.(\w+)", dispatch_content)


def check_tool_coverage(
    tools_content: str,
    dispatch_content: str,
) -> list[str]:
    errors = []
    names = extract_tool_names(tools_content)
    unique_names = list(dict.fromkeys(names))
    dispatched = extract_dispatch_tool_references(dispatch_content)
    unique_dispatched = list(dict.fromkeys(dispatched))

    if not unique_names:
        errors.append(
            "MCPTools.swift must declare at least one tool via MCPToolName.<property>"
        )
        return errors

    if not unique_dispatched:
        errors.append("MCPDispatch*.swift must reference at least one MCPToolName.<property>")

    if len(unique_names) != EXPECTED_TOOL_COUNT:
        errors.append(
            f"Product contract requires exactly {EXPECTED_TOOL_COUNT} unique tools; found {len(unique_names)}"
        )

    # Duplicate check
    seen: dict[str, int] = {}
    for n in names:
        seen[n] = seen.get(n, 0) + 1
    dupes = [n for n, c in seen.items() if c > 1]
    for d in dupes:
        errors.append(f"Duplicate tool declaration in MCPTools.swift: {d}")

    # Coverage check — mirror MCPToolCoverageTests.swift exactly.
    missing = []
    for name in unique_names:
        if f"MCPToolName.{name}" not in dispatch_content:
            missing.append(name)

    if missing:
        errors.append(
            f"MCPDispatch*.swift is missing case(s) for {len(missing)} tool(s): "
            + ", ".join(missing)
        )
    return errors


def main() -> int:
    boundary_src = _read(BOUNDARY_PATH)
    dispatch_src = "\n".join(_read(path) for path in DISPATCH_PATHS)
    primary_dispatch_src = _read(DISPATCH_PATHS[0])
    tools_src = _read(TOOLS_PATH)

    errors: list[str] = []
    errors += check_boundary(boundary_src)
    errors += check_dispatch_structure(primary_dispatch_src)
    errors += check_tool_coverage(tools_src, dispatch_src)

    declared_count = len(dict.fromkeys(extract_tool_names(tools_src)))
    dispatched_count = len(dict.fromkeys(extract_dispatch_tool_references(dispatch_src)))
    if errors:
        for e in errors:
            print(f"FAIL: {e}", file=sys.stderr)
        return 1

    print(
        "OK: MCP boundary valid — "
        f"{declared_count} tools declared, {dispatched_count} referenced across MCPDispatch*.swift."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
