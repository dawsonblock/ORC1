#!/bin/bash
# Shared Swift toolchain bootstrap for Oracle OS build and verification scripts.

ORACLE_PREFERRED_XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
ORACLE_SELECTED_DEVELOPER_DIR="${DEVELOPER_DIR:-}"
declare -a ORACLE_SWIFT_CMD=("swift")
ORACLE_SWIFT_INVOCATION="swift"

oracle_configure_swift_toolchain() {
    ORACLE_SELECTED_DEVELOPER_DIR="${DEVELOPER_DIR:-}"

    if ! command -v xcrun >/dev/null 2>&1; then
        echo "ERROR: xcrun is required to build or verify Oracle OS. Install Xcode or the Apple Command Line Tools." >&2
        return 1
    fi

    if [[ -z "$ORACLE_SELECTED_DEVELOPER_DIR" && -d "$ORACLE_PREFERRED_XCODE_DEVELOPER_DIR" ]]; then
        ORACLE_SELECTED_DEVELOPER_DIR="$ORACLE_PREFERRED_XCODE_DEVELOPER_DIR"
        export DEVELOPER_DIR="$ORACLE_SELECTED_DEVELOPER_DIR"
    fi

    ORACLE_SWIFT_CMD=("xcrun" "swift")
    if [[ -n "$ORACLE_SELECTED_DEVELOPER_DIR" ]]; then
        ORACLE_SWIFT_INVOCATION="DEVELOPER_DIR=$ORACLE_SELECTED_DEVELOPER_DIR xcrun swift"
    else
        ORACLE_SWIFT_INVOCATION="xcrun swift"
    fi

    if ! "${ORACLE_SWIFT_CMD[@]}" --version >/dev/null 2>&1; then
        if [[ -n "$ORACLE_SELECTED_DEVELOPER_DIR" ]]; then
            echo "ERROR: Failed to run $ORACLE_SWIFT_INVOCATION. Check that DEVELOPER_DIR points to a valid Apple developer toolchain." >&2
        else
            echo "ERROR: Failed to run xcrun swift. Install Xcode or the Apple Command Line Tools." >&2
        fi
        return 1
    fi
}

oracle_require_swift_toolchain() {
    oracle_configure_swift_toolchain || exit 1
}

oracle_swift_build_bin_path() {
    local configuration="$1"
    "${ORACLE_SWIFT_CMD[@]}" build -c "$configuration" --show-bin-path
}

oracle_resolved_product_binary_path() {
    local configuration="$1"
    local product="$2"
    local bin_path

    bin_path="$(oracle_swift_build_bin_path "$configuration")" || return 1
    printf '%s/%s\n' "$bin_path" "$product"
}