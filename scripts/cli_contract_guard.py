#!/usr/bin/env python3
"""Guard the documented oracle CLI contract against drift in main.swift."""

from __future__ import annotations

from pathlib import Path
import re
import sys


REPO_ROOT = Path(__file__).resolve().parent.parent
PRODUCT_CONTRACT = REPO_ROOT / "docs" / "PRODUCT_CONTRACT.md"
MAIN_SWIFT = REPO_ROOT / "Sources" / "oracle" / "main.swift"


def parse_contract() -> tuple[list[str], dict[str, list[str]]]:
    text = PRODUCT_CONTRACT.read_text(encoding="utf-8")
    match = re.search(
        r"<!-- CLI_CONTRACT_START -->\n(.*?)\n<!-- CLI_CONTRACT_END -->",
        text,
        re.DOTALL,
    )
    if not match:
        raise ValueError("Missing CLI contract block in docs/PRODUCT_CONTRACT.md")

    primary: list[str] = []
    aliases: dict[str, list[str]] = {}
    in_aliases = False

    for raw_line in match.group(1).splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("primary:"):
            primary = [item.strip() for item in stripped.split(":", 1)[1].split(",") if item.strip()]
            continue
        if stripped == "aliases:":
            in_aliases = True
            continue
        if in_aliases:
            if not raw_line.startswith("  "):
                raise ValueError(f"Malformed alias line in CLI contract block: {raw_line!r}")
            name, values = stripped.split(":", 1)
            aliases[name.strip()] = [item.strip() for item in values.split(",") if item.strip()]

    if not primary:
        raise ValueError("CLI contract block did not define any primary commands")

    return primary, aliases


def parse_main_cases() -> tuple[list[str], dict[str, list[str]]]:
    text = MAIN_SWIFT.read_text(encoding="utf-8")
    match = re.search(r"switch command \{(.*?)\n\s*default:", text, re.DOTALL)
    if not match:
        raise ValueError("Could not find command switch in Sources/oracle/main.swift")

    primary: list[str] = []
    aliases: dict[str, list[str]] = {}
    for line in match.group(1).splitlines():
        stripped = line.strip()
        if not stripped.startswith("case "):
            continue
        entries = re.findall(r'"([^"]+)"', stripped)
        if not entries:
            continue
        primary.append(entries[0])
        if len(entries) > 1:
            aliases[entries[0]] = entries[1:]

    return primary, aliases


def parse_usage_commands() -> list[str]:
    text = MAIN_SWIFT.read_text(encoding="utf-8")
    match = re.search(r"Commands:\n(.*?)\n\s*Get started:", text, re.DOTALL)
    if not match:
        raise ValueError("Could not find Commands block in printUsage()")

    commands: list[str] = []
    for line in match.group(1).splitlines():
        usage_match = re.match(r"\s*([a-z][a-z0-9_-]*)\s{2,}", line)
        if usage_match:
            commands.append(usage_match.group(1))

    if not commands:
        raise ValueError("Usage block did not expose any commands")

    return commands


def main() -> int:
    contract_primary, contract_aliases = parse_contract()
    switch_primary, switch_aliases = parse_main_cases()
    usage_primary = parse_usage_commands()

    errors: list[str] = []
    if contract_primary != switch_primary:
        errors.append(
            "Primary command drift between docs/PRODUCT_CONTRACT.md and Sources/oracle/main.swift: "
            f"docs={contract_primary} main={switch_primary}"
        )
    if contract_primary != usage_primary:
        errors.append(
            "Primary command drift between docs/PRODUCT_CONTRACT.md and printUsage(): "
            f"docs={contract_primary} usage={usage_primary}"
        )
    if contract_aliases != switch_aliases:
        errors.append(
            "Alias drift between docs/PRODUCT_CONTRACT.md and Sources/oracle/main.swift: "
            f"docs={contract_aliases} main={switch_aliases}"
        )

    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1

    print(
        "OK: oracle CLI contract matches docs/PRODUCT_CONTRACT.md, Sources/oracle/main.swift, "
        "and printUsage()."
    )
    print(f"Primary commands: {', '.join(contract_primary)}")
    if contract_aliases:
        for command, aliases in contract_aliases.items():
            print(f"Aliases: {command} -> {', '.join(aliases)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())