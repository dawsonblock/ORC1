#!/usr/bin/env python3
"""mcp_boundary_guard.py — CI enforcement for MCP tool contract completeness.

Checks:
  1. MCPBoundary.swift defines JSONValue, MCPToolRequest, MCPToolResponse, MCPContent.
  2. MCPDispatch.swift contains a dispatch function with typed parameter extraction.
  3. Every tool declared in MCPTools.swift has a corresponding case in MCPDispatch.swift.
  4. No tool name appears more than once in MCPTools.swift (no duplicates).

Exit codes:
  0 — all checks pass
  1 — one or more checks failed (details printed to stderr)
"""
import os
import re
import sys


BOUNDARY_PATH  = "Sources/OracleOS/MCP/MCPBoundary.swift"
DISPATCH_PATH  = "Sources/OracleOS/MCP/MCPDispatch.swift"
TOOLS_PATH     = "Sources/OracleOS/MCP/MCPTools.swift"


def _read(path: str) -> str:
    if not os.path.exists(path):
        print(f"ERROR: required file not found: {path}", file=sys.stderr)
        sys.exit(1)
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def check_boundary(content: str) -> list[str]:
    errors = []
    required = ["enum JSONValue", "struct MCPToolRequest", "struct MCPToolResponse", "enum MCPContent"]
    for token in required:
        if token not in content:
            errors.append(f"MCPBoundary.swift missing: {token}")
    return errors


def check_dispatch_structure(content: str) -> list[str]:
    errors = []
    if "func dispatch(request: MCPToolRequest)" not in content:
        errors.append("MCPDispatch.swift missing: func dispatch(request: MCPToolRequest)")
    if "formatTypedResult" not in content:
        errors.append("MCPDispatch.swift missing: formatTypedResult")
    return errors


def extract_tool_names(tools_content: str) -> list[str]:
    """Return list of tool names declared in MCPTools.swift (order preserved)."""
    return re.findall(r'name:\s*"(oracle_\w+)"', tools_content)


def check_tool_coverage(tools_content: str, dispatch_content: str) -> list[str]:
    errors = []
    names = extract_tool_names(tools_content)

    # Duplicate check
    seen: dict[str, int] = {}
    for n in names:
        seen[n] = seen.get(n, 0) + 1
    dupes = [n for n, c in seen.items() if c > 1]
    for d in dupes:
        errors.append(f"Duplicate tool declaration in MCPTools.swift: {d}")

    # Coverage check — each tool name must appear inside dispatch()
    # We search for the name as a quoted string literal in dispatch_content.
    missing = []
    for name in dict.fromkeys(names):  # deduplicated, order preserved
        pattern = f'"{name}"'
        if pattern not in dispatch_content:
            missing.append(name)

    if missing:
        errors.append(
            f"MCPDispatch.swift is missing case(s) for {len(missing)} tool(s): "
            + ", ".join(missing)
        )
    return errors


def main() -> int:
    boundary_src  = _read(BOUNDARY_PATH)
    dispatch_src  = _read(DISPATCH_PATH)
    tools_src     = _read(TOOLS_PATH)

    errors: list[str] = []
    errors += check_boundary(boundary_src)
    errors += check_dispatch_structure(dispatch_src)
    errors += check_tool_coverage(tools_src, dispatch_src)

    tool_count = len(dict.fromkeys(extract_tool_names(tools_src)))
    if errors:
        for e in errors:
            print(f"FAIL: {e}", file=sys.stderr)
        return 1

    print(f"OK: MCP boundary valid — {tool_count} tools declared and dispatched.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
