#!/usr/bin/env python3
"""Guard the vision sidecar schema and runtime payload against Swift contract drift."""

from __future__ import annotations

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import re
import sys
from types import ModuleType
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent
SWIFT_CONTRACT = REPO_ROOT / "Sources" / "OracleOS" / "Contracts" / "VisionSidecarContract.swift"
PYTHON_SCHEMA = REPO_ROOT / "vision-sidecar" / "schema" / "endpoints.py"
PYTHON_ELEMENT = REPO_ROOT / "vision-sidecar" / "schema" / "element.py"


def load_module(path: Path, name: str) -> ModuleType:
    spec = spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ValueError(f"Could not load module from {path}")
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def extract_block(text: str, token: str) -> str:
    start_index = text.find(token)
    if start_index == -1:
        raise ValueError(f"Missing token: {token}")

    brace_start = text.find("{", start_index)
    if brace_start == -1:
        raise ValueError(f"Missing opening brace after token: {token}")

    depth = 0
    for index in range(brace_start, len(text)):
        character = text[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return text[brace_start + 1 : index]

    raise ValueError(f"Unterminated block for token: {token}")


def parse_swift_properties(struct_body: str) -> dict[str, str]:
    properties: dict[str, str] = {}
    for raw_line in struct_body.splitlines():
        stripped = raw_line.strip()
        if not stripped.startswith("public let "):
            continue
        declaration = stripped[len("public let ") :]
        name, type_expression = declaration.split(":", 1)
        properties[name.strip()] = type_expression.split("//", 1)[0].strip()
    return properties


def parse_swift_coding_keys(struct_body: str) -> dict[str, str]:
    if "CodingKeys" not in struct_body:
        return {}

    coding_keys_body = extract_block(struct_body, "enum CodingKeys")
    mapping: dict[str, str] = {}
    for raw_line in coding_keys_body.splitlines():
        stripped = raw_line.strip()
        if not stripped.startswith("case "):
            continue
        clause = stripped[len("case ") :].split("//", 1)[0].strip()
        if "=" in clause:
            names_text, key_text = clause.split("=", 1)
            names = [name.strip() for name in names_text.split(",") if name.strip()]
            key = key_text.strip().strip('"')
            if len(names) != 1:
                raise ValueError(f"Unsupported CodingKeys clause: {raw_line!r}")
            mapping[names[0]] = key
        else:
            names = [name.strip() for name in clause.split(",") if name.strip()]
            for name in names:
                mapping[name] = name
    return mapping


def swift_type_to_schema_types(type_expression: str) -> set[str]:
    normalized = type_expression.replace(" ", "")
    is_optional = normalized.endswith("?")
    if is_optional:
        normalized = normalized[:-1]

    if normalized.startswith("[") and normalized.endswith("]"):
        schema_types = {"list"}
    elif normalized == "String":
        schema_types = {"str"}
    elif normalized == "Double":
        schema_types = {"float"}
    elif normalized == "Int":
        schema_types = {"int"}
    elif normalized == "Bool":
        schema_types = {"bool"}
    else:
        schema_types = {"object"}

    if is_optional:
        schema_types.add("None")
    return schema_types


def parse_swift_struct_schema(text: str, struct_name: str) -> dict[str, set[str]]:
    struct_body = extract_block(text, f"public struct {struct_name}")
    coding_keys = parse_swift_coding_keys(struct_body)
    schema: dict[str, set[str]] = {}
    for property_name, type_expression in parse_swift_properties(struct_body).items():
        json_key = coding_keys.get(property_name, property_name)
        schema[json_key] = swift_type_to_schema_types(type_expression)
    return schema


def parse_swift_endpoints(text: str) -> dict[str, str]:
    enum_body = extract_block(text, "public enum VisionSidecarEndpoint")
    endpoints: dict[str, str] = {}
    for raw_line in enum_body.splitlines():
        stripped = raw_line.strip()
        match = re.match(r'public static let (\w+) = "([^"]+)"', stripped)
        if match:
            endpoints[match.group(1)] = match.group(2)
    return endpoints


def python_schema_types(value: Any) -> set[str]:
    if isinstance(value, tuple):
        collected: set[str] = set()
        for item in value:
            collected |= python_schema_types(item)
        return collected
    if value is type(None):
        return {"None"}
    if value is str:
        return {"str"}
    if value is float:
        return {"float"}
    if value is int:
        return {"int"}
    if value is bool:
        return {"bool"}
    if value is list:
        return {"list"}
    return {"object"}


def parse_python_schema(schema: dict[str, Any]) -> dict[str, set[str]]:
    return {key: python_schema_types(value) for key, value in schema.items()}


def parse_runtime_element_keys(text: str) -> set[str]:
    block = extract_block(text, "def to_dict")
    return set(re.findall(r'"([^"]+)"\s*:', block))


def compare_schema(
    label: str,
    swift_schema: dict[str, set[str]],
    python_schema: dict[str, set[str]],
    errors: list[str],
) -> None:
    swift_keys = set(swift_schema)
    python_keys = set(python_schema)
    if swift_keys != python_keys:
        errors.append(
            f"{label} key drift: swift={sorted(swift_keys)} python={sorted(python_keys)}"
        )

    for key in sorted(swift_keys & python_keys):
        swift_types = swift_schema[key] - {"None"}
        python_types = python_schema[key] - {"None"}
        if swift_types != python_types:
            errors.append(
                f"{label}.{key} type drift: swift={sorted(swift_schema[key])} "
                f"python={sorted(python_schema[key])}"
            )


def main() -> int:
    swift_text = SWIFT_CONTRACT.read_text(encoding="utf-8")
    python_schema_module = load_module(PYTHON_SCHEMA, "vision_endpoints_schema")
    runtime_element_text = PYTHON_ELEMENT.read_text(encoding="utf-8")

    errors: list[str] = []

    swift_endpoints = parse_swift_endpoints(swift_text)
    python_endpoints = {
        "health": python_schema_module.ENDPOINT_HEALTH,
        "ground": python_schema_module.ENDPOINT_GROUND,
        "detect": python_schema_module.ENDPOINT_DETECT,
        "parse": python_schema_module.ENDPOINT_PARSE,
    }
    if swift_endpoints != python_endpoints:
        errors.append(
            f"Endpoint drift: swift={swift_endpoints} python={python_endpoints}"
        )

    compare_schema(
        "VisionGroundRequest",
        parse_swift_struct_schema(swift_text, "VisionGroundRequest"),
        parse_python_schema(python_schema_module.GROUND_REQUEST_SCHEMA),
        errors,
    )
    compare_schema(
        "VisionGroundResponse",
        parse_swift_struct_schema(swift_text, "VisionGroundResponse"),
        parse_python_schema(python_schema_module.GROUND_RESPONSE_SCHEMA),
        errors,
    )
    compare_schema(
        "VisionDetectRequest",
        parse_swift_struct_schema(swift_text, "VisionDetectRequest"),
        parse_python_schema(python_schema_module.DETECT_REQUEST_SCHEMA),
        errors,
    )
    compare_schema(
        "VisionSidecarElement",
        parse_swift_struct_schema(swift_text, "VisionSidecarElement"),
        parse_python_schema(python_schema_module.DETECT_ELEMENT_SCHEMA),
        errors,
    )
    compare_schema(
        "VisionDetectResponse",
        parse_swift_struct_schema(swift_text, "VisionDetectResponse"),
        parse_python_schema(python_schema_module.DETECT_RESPONSE_SCHEMA),
        errors,
    )
    compare_schema(
        "VisionParseRequest",
        parse_swift_struct_schema(swift_text, "VisionParseRequest"),
        parse_python_schema(python_schema_module.PARSE_REQUEST_SCHEMA),
        errors,
    )
    compare_schema(
        "VisionParseResponse",
        parse_swift_struct_schema(swift_text, "VisionParseResponse"),
        parse_python_schema(python_schema_module.PARSE_RESPONSE_SCHEMA),
        errors,
    )
    compare_schema(
        "VisionHealthResponse",
        parse_swift_struct_schema(swift_text, "VisionHealthResponse"),
        parse_python_schema(python_schema_module.HEALTH_RESPONSE_SCHEMA),
        errors,
    )

    runtime_element_keys = parse_runtime_element_keys(runtime_element_text)
    schema_element_keys = set(python_schema_module.DETECT_ELEMENT_SCHEMA)
    if runtime_element_keys != schema_element_keys:
        errors.append(
            "Runtime element payload drift: "
            f"element.py={sorted(runtime_element_keys)} endpoints.py={sorted(schema_element_keys)}"
        )

    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1

    print(
        "OK: vision sidecar Swift contract, Python endpoint schema, and runtime element payload agree."
    )
    print(f"Endpoints: {swift_endpoints}")
    print(f"Element keys: {sorted(runtime_element_keys)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())