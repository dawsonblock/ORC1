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
#   build-output.txt  — raw swift build output
#   test-output.txt   — raw swift test output
#   verify-result.txt — summary with timestamps and pass/fail verdict

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_LOG="$REPO_ROOT/build-output.txt"
TEST_LOG="$REPO_ROOT/test-output.txt"
RESULT_LOG="$REPO_ROOT/verify-result.txt"

MODE="all"
if [[ "${1:-}" == "--test-only" ]]; then MODE="test"; fi
if [[ "${1:-}" == "--build-only" ]]; then MODE="build"; fi

cd "$REPO_ROOT"

echo "=== ORC1 Verify Build ===" | tee "$RESULT_LOG"
echo "Repo:    $REPO_ROOT" | tee -a "$RESULT_LOG"
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$RESULT_LOG"
echo "Mode:    $MODE" | tee -a "$RESULT_LOG"
echo "" | tee -a "$RESULT_LOG"

BUILD_PASS=true
TEST_PASS=true

# --- Build ---
if [[ "$MODE" == "all" || "$MODE" == "build" ]]; then
    echo "--- swift build -c release ---" | tee -a "$RESULT_LOG"
    if swift build -c release 2>&1 | tee "$BUILD_LOG"; then
        echo "BUILD: PASS" | tee -a "$RESULT_LOG"
    else
        echo "BUILD: FAIL" | tee -a "$RESULT_LOG"
        BUILD_PASS=false
    fi
    echo "" | tee -a "$RESULT_LOG"
fi

# --- Test ---
if [[ "$MODE" == "all" || "$MODE" == "test" ]]; then
    echo "--- swift test ---" | tee -a "$RESULT_LOG"
    if swift test 2>&1 | tee "$TEST_LOG"; then
        echo "TEST: PASS" | tee -a "$RESULT_LOG"
    else
        echo "TEST: FAIL" | tee -a "$RESULT_LOG"
        TEST_PASS=false
    fi
    echo "" | tee -a "$RESULT_LOG"
fi

# --- Boundary guard ---
if [[ "$MODE" == "all" ]]; then
    echo "--- mcp_boundary_guard.py ---" | tee -a "$RESULT_LOG"
    if python3 "$REPO_ROOT/scripts/mcp_boundary_guard.py" 2>&1 | tee -a "$RESULT_LOG"; then
        echo "BOUNDARY_GUARD: PASS" | tee -a "$RESULT_LOG"
    else
        echo "BOUNDARY_GUARD: FAIL" | tee -a "$RESULT_LOG"
        BUILD_PASS=false
    fi
    echo "" | tee -a "$RESULT_LOG"
fi

# --- Summary ---
echo "Finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$RESULT_LOG"
echo "" | tee -a "$RESULT_LOG"

VERDICT="PASS"
if [[ "$BUILD_PASS" == "false" || "$TEST_PASS" == "false" ]]; then
    VERDICT="FAIL"
fi

echo "=== VERDICT: $VERDICT ===" | tee -a "$RESULT_LOG"
echo "" | tee -a "$RESULT_LOG"
echo "Evidence files:"
echo "  Build log: $BUILD_LOG"
echo "  Test log:  $TEST_LOG"
echo "  Summary:   $RESULT_LOG"

if [[ "$VERDICT" == "FAIL" ]]; then
    exit 1
fi
