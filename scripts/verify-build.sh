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
RESULT_LOG="$EVIDENCE_DIR/verify-result.txt"

MODE="all"
if [[ "${1:-}" == "--test-only" ]]; then MODE="test"; fi
if [[ "${1:-}" == "--build-only" ]]; then MODE="build"; fi

cd "$REPO_ROOT"
mkdir -p "$EVIDENCE_DIR"

echo "=== ORC1 Verify Build ===" | tee "$RESULT_LOG"
echo "Repo:    $REPO_ROOT" | tee -a "$RESULT_LOG"
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$RESULT_LOG"
echo "Mode:    $MODE" | tee -a "$RESULT_LOG"
echo "" | tee -a "$RESULT_LOG"

BUILD_PASS=true
TEST_PASS=true
GUARDS_PASS=true
FACTS_PASS=true

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

# --- Boundary guards ---
if [[ "$MODE" == "all" ]]; then
    echo "--- generate_repo_facts.py --check ---" | tee -a "$RESULT_LOG"
    if python3 "$REPO_ROOT/scripts/generate_repo_facts.py" --check 2>&1 | tee -a "$RESULT_LOG"; then
        echo "REPO_FACTS: PASS" | tee -a "$RESULT_LOG"
    else
        echo "REPO_FACTS: FAIL" | tee -a "$RESULT_LOG"
        FACTS_PASS=false
    fi
    echo "" | tee -a "$RESULT_LOG"

    echo "--- mcp_boundary_guard.py ---" | tee -a "$RESULT_LOG"
    if python3 "$REPO_ROOT/scripts/mcp_boundary_guard.py" 2>&1 | tee -a "$RESULT_LOG"; then
        echo "MCP_BOUNDARY_GUARD: PASS" | tee -a "$RESULT_LOG"
    else
        echo "MCP_BOUNDARY_GUARD: FAIL" | tee -a "$RESULT_LOG"
        GUARDS_PASS=false
    fi
    echo "" | tee -a "$RESULT_LOG"

    echo "--- architecture_guard.py ---" | tee -a "$RESULT_LOG"
    if python3 "$REPO_ROOT/scripts/architecture_guard.py" 2>&1 | tee -a "$RESULT_LOG"; then
        echo "ARCHITECTURE_GUARD: PASS" | tee -a "$RESULT_LOG"
    else
        echo "ARCHITECTURE_GUARD: FAIL" | tee -a "$RESULT_LOG"
        GUARDS_PASS=false
    fi
    echo "" | tee -a "$RESULT_LOG"

    echo "--- execution_boundary_guard.py ---" | tee -a "$RESULT_LOG"
    if python3 "$REPO_ROOT/scripts/execution_boundary_guard.py" 2>&1 | tee -a "$RESULT_LOG"; then
        echo "EXECUTION_BOUNDARY_GUARD: PASS" | tee -a "$RESULT_LOG"
    else
        echo "EXECUTION_BOUNDARY_GUARD: FAIL" | tee -a "$RESULT_LOG"
        GUARDS_PASS=false
    fi
    echo "" | tee -a "$RESULT_LOG"
fi

# --- Summary ---
echo "Finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$RESULT_LOG"
echo "" | tee -a "$RESULT_LOG"

VERDICT="PASS"
if [[ "$BUILD_PASS" == "false" || "$TEST_PASS" == "false" || "$GUARDS_PASS" == "false" || "$FACTS_PASS" == "false" ]]; then
    VERDICT="FAIL"
fi

echo "=== VERDICT: $VERDICT ===" | tee -a "$RESULT_LOG"
echo "" | tee -a "$RESULT_LOG"
echo "Evidence files:" | tee -a "$RESULT_LOG"
echo "  Build log: $BUILD_LOG" | tee -a "$RESULT_LOG"
echo "  Test log:  $TEST_LOG" | tee -a "$RESULT_LOG"
echo "  Summary:   $RESULT_LOG" | tee -a "$RESULT_LOG"

if [[ "$VERDICT" == "FAIL" ]]; then
    exit 1
fi
