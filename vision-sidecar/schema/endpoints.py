"""
vision-sidecar/schema/endpoints.py
Canonical endpoint schema definitions for the Oracle OS vision sidecar.

These definitions are the Python-side authority for request/response shapes.
Any change here must be reflected in VisionSidecarContract.swift (Swift side)
and vice-versa. See Sources/OracleOS/Contracts/VisionSidecarContract.swift.

Default port: 9876 (localhost only).
"""

from __future__ import annotations

DEFAULT_PORT: int = 9876
BASE_URL: str = f"http://127.0.0.1:{DEFAULT_PORT}"

# ── Endpoint paths ────────────────────────────────────────────────────────────

ENDPOINT_HEALTH: str = "/health"
ENDPOINT_GROUND: str = "/ground"
ENDPOINT_DETECT: str = "/detect"
ENDPOINT_PARSE: str = "/parse"

# ── GET /health ───────────────────────────────────────────────────────────────

HEALTH_RESPONSE_SCHEMA: dict = {
    "status": str,          # "ready" | "idle"
    "version": str,         # e.g. "2.0.6"
    "models_loaded": list,  # e.g. ["showui-2b"]
    "model_path": str,
    "model_exists": bool,
    "vlm_load_error": (str, type(None)),
    "idle_timeout": int,    # seconds; 0 = no timeout
    "pid": int,
}

# ── POST /ground ──────────────────────────────────────────────────────────────

GROUND_REQUEST_SCHEMA: dict = {
    # Required
    "image": str,           # base64-encoded PNG
    "description": str,     # natural-language target description
    # Optional (with defaults)
    "screen_w": float,      # logical screen width; default 1728
    "screen_h": float,      # logical screen height; default 1117
    "crop_box": list,       # [x1, y1, x2, y2] in logical points; omit for full-screen
}

GROUND_REQUIRED_FIELDS: tuple[str, ...] = ("image", "description")

GROUND_RESPONSE_SCHEMA: dict = {
    # Success fields
    "x": float,             # logical X coordinate
    "y": float,             # logical Y coordinate
    "normalized_x": float,  # x / screen_w, in [0, 1]
    "normalized_y": float,  # y / screen_h, in [0, 1]
    "method": str,          # "full-screen" | "crop-based"
    "crop_box": list,       # echoed crop region, only present for crop-based
    # Failure field (populated on error; other fields may be absent)
    "error": (str, type(None)),
}

# ── POST /detect ──────────────────────────────────────────────────────────────

DETECT_REQUEST_SCHEMA: dict = {
    # Required
    "image": str,           # base64-encoded PNG
    # Optional (with defaults)
    "screen_w": float,      # logical screen width; default 1728
    "screen_h": float,      # logical screen height; default 1117
}

DETECT_REQUIRED_FIELDS: tuple[str, ...] = ("image",)

DETECT_ELEMENT_SCHEMA: dict = {
    "role": (str, type(None)),
    "label": (str, type(None)),
    "x": float,
    "y": float,
    "width": float,
    "height": float,
    "confidence": (float, type(None)),
}

DETECT_RESPONSE_SCHEMA: dict = {
    "status": str,          # "success"
    "elements": list,       # list of DETECT_ELEMENT_SCHEMA dicts
    "count": int,
    "suggestion": (str, type(None)),
    "error": (str, type(None)),
}

# ── POST /parse ───────────────────────────────────────────────────────────────

PARSE_REQUEST_SCHEMA: dict = {
    # Required
    "image": str,           # base64-encoded PNG
    # Optional (with defaults)
    "screen_w": float,      # logical screen width; default 1728
    "screen_h": float,      # logical screen height; default 1117
}

PARSE_REQUIRED_FIELDS: tuple[str, ...] = ("image",)

# Parse response shape is determined by ScreenParser and may evolve.
# The stable surface exported to Swift matches these fields.
PARSE_RESPONSE_SCHEMA: dict = {
    "status": (str, type(None)),
    "elements": (list, type(None)),
    "count": (int, type(None)),
    "error": (str, type(None)),
}

# ── Registry ──────────────────────────────────────────────────────────────────

ALL_ENDPOINTS: list[dict] = [
    {
        "path": ENDPOINT_HEALTH,
        "method": "GET",
        "description": "Check if models are loaded and server is ready.",
        "request_schema": None,
        "response_schema": HEALTH_RESPONSE_SCHEMA,
    },
    {
        "path": ENDPOINT_GROUND,
        "method": "POST",
        "description": "Find precise screen coordinates for a described UI element.",
        "request_schema": GROUND_REQUEST_SCHEMA,
        "required_fields": GROUND_REQUIRED_FIELDS,
        "response_schema": GROUND_RESPONSE_SCHEMA,
    },
    {
        "path": ENDPOINT_DETECT,
        "method": "POST",
        "description": "Detect all interactive UI elements on the screenshot.",
        "request_schema": DETECT_REQUEST_SCHEMA,
        "required_fields": DETECT_REQUIRED_FIELDS,
        "response_schema": DETECT_RESPONSE_SCHEMA,
    },
    {
        "path": ENDPOINT_PARSE,
        "method": "POST",
        "description": "Parse screen into a structured element map (YOLO + VLM).",
        "request_schema": PARSE_REQUEST_SCHEMA,
        "required_fields": PARSE_REQUIRED_FIELDS,
        "response_schema": PARSE_RESPONSE_SCHEMA,
    },
]
