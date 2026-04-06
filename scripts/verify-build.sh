#!/bin/bash
# verify-build.sh — Build and test proof baseline.
#
# Produces machine-readable evidence that the repo compiles cleanly
# and all tests pass. Run this before any significant commit.
#
# Usage:
#   ./scripts/verify-build.sh
#   ./scripts/verify-build.sh --test-only
#   ./scripts/verify-build.sh --build-only
#
# Outputs:
#   local/verify/latest/build-output.txt  — raw swift build output
#   local/verify/latest/test-output.txt   — raw swift test output
#   local/verify/latest/verify-result.txt — summary with timestamps and pass/fail verdict

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVIDENCE_DIR="$REPO_ROOT/local/verify/latest"
BUILD_LOG="$EVIDENCE_DIR/build-output.txt"
TEST_LOG="$EVIDENCE_DIR/test-output.txt"
ENVIRONMENT_LOG="$EVIDENCE_DIR/environment.txt"
RESULT_LOG="$EVIDENCE_DIR/verify-result.txt"

MODE="all"
if [[ "${1:-}" == "--test-only" ]]; then MODE="test"; fi
if [[ "${1:-}" == "--build-only" ]]; then MODE="build"; fi

cd "$REPO_ROOT"
mkdir -p "$EVIDENCE_DIR"

: > "$BUILD_LOG"
: > "$TEST_LOG"
: > "$ENVIRONMENT_LOG"
: > "$RESULT_LOG"

write_result() {
    echo "$1" | tee -a "$RESULT_LOG"
}

write_section() {
    write_result "--- $1 ---"
}

complete_verification() {
    local verdict="$1"

    write_result "Finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    write_result ""
    write_result "=== VERDICT: $verdict ==="
    write_result ""
    write_result "Evidence files:"
    write_result "  Environment: $ENVIRONMENT_LOG"
    write_result "  Build log:    $BUILD_LOG"
    write_result "  Test log:     $TEST_LOG"
    write_result "  Summary:      $RESULT_LOG"

    if [[ "$verdict" == "FAIL" ]]; then
        exit 1
    fi
}

fail_step() {
    local label="$1"
    local message="$2"

    write_result "$label: FAIL"
    write_result "$message"
    write_result ""
    complete_verification "FAIL"
}

record_environment() {
    {
        echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "mode=$MODE"
        echo "pwd=$REPO_ROOT"
        echo "uname=$(uname -a)"
        if command -v sw_vers >/dev/null 2>&1; then
            echo "sw_vers=$(sw_vers -productVersion)"
        fi
        if command -v swift >/dev/null 2>&1; then
            echo "swift_version=$(swift --version | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')"
        fi
        if command -v python3 >/dev/null 2>&1; then
            echo "python_version=$(python3 --version 2>&1)"
        fi
    } > "$ENVIRONMENT_LOG"
}

require_supported_runtime_platform() {
    local platform
    platform="$(uname -s)"
    write_section "runtime platform"

    if [[ "$platform" != "Darwin" ]]; then
        fail_step "RUNTIME_PLATFORM" "Unsupported runtime verification platform: $platform. The supported swift build and test path is macOS 14+ only."
    fi

    if command -v sw_vers >/dev/null 2>&1; then
        local product_version
        local major_version
        product_version="$(sw_vers -productVersion)"
        major_version="${product_version%%.*}"
        if [[ "$major_version" =~ ^[0-9]+$ ]] && (( major_version < 14 )); then
            fail_step "RUNTIME_PLATFORM" "Unsupported macOS runtime verification version: $product_version. The supported swift build and test path is macOS 14+ only."
        fi
        write_result "RUNTIME_PLATFORM: PASS ($platform $product_version)"
    else
        write_result "RUNTIME_PLATFORM: PASS ($platform)"
    fi
    write_result ""
}

run_logged_command() {
    local label="$1"
    local description="$2"
    local log_path="$3"
    shift 3

    write_section "$description"
    if "$@" 2>&1 | tee "$log_path"; then
        write_result "$label: PASS"
        write_result ""
    else
        fail_step "$label" "Command failed: $description"
    fi
}

run_guard_command() {
    local label="$1"
    local description="$2"
    shift 2

    write_section "$description"
    if "$@" 2>&1 | tee -a "$RESULT_LOG"; then
        write_result "$label: PASS"
        write_result ""
    else
        fail_step "$label" "Command failed: $description"
    fi
}

echo "=== ORC1 Verify Build ===" | tee -a "$RESULT_LOG"
echo "Repo:    $REPO_ROOT" | tee -a "$RESULT_LOG"
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$RESULT_LOG"
echo "Mode:    $MODE" | tee -a "$RESULT_LOG"
echo "" | tee -a "$RESULT_LOG"

record_environment
write_result "Environment: $ENVIRONMENT_LOG"
write_result ""
require_supported_runtime_platform

# --- Build ---
if [[ "$MODE" == "all" || "$MODE" == "build" ]]; then
    run_logged_command "BUILD" "swift build -c release" "$BUILD_LOG" swift build -c release
fi

# --- Test ---
if [[ "$MODE" == "all" || "$MODE" == "test" ]]; then
    run_logged_command "TEST" "swift test" "$TEST_LOG" swift test
fi

# --- Boundary guards ---
if [[ "$MODE" == "all" ]]; then
    run_guard_command "REPO_FACTS" "generate_repo_facts.py --check" python3 "$REPO_ROOT/scripts/generate_repo_facts.py" --check
    run_guard_command "MCP_BOUNDARY_GUARD" "mcp_boundary_guard.py" python3 "$REPO_ROOT/scripts/mcp_boundary_guard.py"
    run_guard_command "ARCHITECTURE_GUARD" "architecture_guard.py" python3 "$REPO_ROOT/scripts/architecture_guard.py"
    run_guard_command "EXECUTION_BOUNDARY_GUARD" "execution_boundary_guard.py" python3 "$REPO_ROOT/scripts/execution_boundary_guard.py"
fi

complete_verification "PASS"
