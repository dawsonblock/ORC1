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
#   local/verify/latest/dependency-resolution-output.txt — raw swift package resolve output
#   local/verify/latest/build-output.txt  — raw swift build output
#   local/verify/latest/cli-smoke-output.txt — raw oracle CLI smoke output
#   local/verify/latest/test-output.txt   — raw swift test output
#   local/verify/latest/verify-result.txt — structured summary with timestamps and pass/fail verdict

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVIDENCE_DIR="$REPO_ROOT/local/verify/latest"
DEPENDENCY_LOG="$EVIDENCE_DIR/dependency-resolution-output.txt"
BUILD_LOG="$EVIDENCE_DIR/build-output.txt"
CLI_SMOKE_LOG="$EVIDENCE_DIR/cli-smoke-output.txt"
TEST_LOG="$EVIDENCE_DIR/test-output.txt"
ENVIRONMENT_LOG="$EVIDENCE_DIR/environment.txt"
RESULT_LOG="$EVIDENCE_DIR/verify-result.txt"
PREFERRED_XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

declare -a VERIFIED_CLI_COMMANDS=()
declare -a VERIFIED_GUARDS=()
declare -a SKIPPED_PHASES=()
declare -a SANITIZED_ENV_VARS=(
    "ORACLE_LLM_API_KEY"
    "ORACLE_LLM_BASE_URL"
    "ORACLE_LLM_MODEL"
    "ORACLE_LLM_PLANNING_MODEL"
    "ORACLE_LLM_REPAIR_MODEL"
    "ORACLE_LLM_BROWSER_MODEL"
    "ORACLE_LLM_RECOVERY_MODEL"
)
declare -a SANITIZED_ENV_ARGS=()
declare -a SWIFT_CMD=("swift")
PLATFORM_STATUS="not-run"
DEPENDENCY_STATUS="not-run"
BUILD_STATUS="not-run"
TEST_STATUS="not-run"
CLI_SMOKE_STATUS="not-run"
DASHBOARD_SMOKE_STATUS="not-run"
GUARD_STATUS="not-run"
FAILURE_LABEL=""
FAILURE_MESSAGE=""
SANITIZED_REASONING_ENV="none detected"
SWIFT_INVOCATION="swift"
SELECTED_DEVELOPER_DIR="${DEVELOPER_DIR:-}"
declare -i DID_BUILD=0
declare -i DID_RESOLVE=0
declare -i DID_TEST=0

MODE="all"
if [[ "${1:-}" == "--test-only" ]]; then MODE="test"; fi
if [[ "${1:-}" == "--build-only" ]]; then MODE="build"; fi

cd "$REPO_ROOT"
mkdir -p "$EVIDENCE_DIR"

: > "$DEPENDENCY_LOG"
: > "$BUILD_LOG"
: > "$CLI_SMOKE_LOG"
: > "$TEST_LOG"
: > "$ENVIRONMENT_LOG"
: > "$RESULT_LOG"

write_result() {
    echo "$1" | tee -a "$RESULT_LOG"
}

write_section() {
    write_result "--- $1 ---"
}

record_skip() {
    SKIPPED_PHASES+=("$1")
}

initialize_sanitized_environment() {
    local present=""
    local variable

    for variable in "${SANITIZED_ENV_VARS[@]}"; do
        SANITIZED_ENV_ARGS+=("-u" "$variable")
        if [[ -n "${!variable:-}" ]]; then
            if [[ -n "$present" ]]; then
                present+=", "
            fi
            present+="$variable"
        fi
    done

    if [[ -n "$present" ]]; then
        SANITIZED_REASONING_ENV="$present"
    fi
}

configure_swift_toolchain() {
    if command -v xcrun >/dev/null 2>&1; then
        if [[ -z "$SELECTED_DEVELOPER_DIR" && -d "$PREFERRED_XCODE_DEVELOPER_DIR" ]]; then
            SELECTED_DEVELOPER_DIR="$PREFERRED_XCODE_DEVELOPER_DIR"
            export DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR"
        fi
        SWIFT_CMD=("xcrun" "swift")
        if [[ -n "$SELECTED_DEVELOPER_DIR" ]]; then
            SWIFT_INVOCATION="DEVELOPER_DIR=$SELECTED_DEVELOPER_DIR xcrun swift"
        else
            SWIFT_INVOCATION="xcrun swift"
        fi
    fi
}

complete_verification() {
    local verdict="$1"

    write_result "Finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    write_result ""
    write_section "verification summary"
    write_result "Platform eligibility: $PLATFORM_STATUS"
    write_result "Sanitized optional reasoning env: $SANITIZED_REASONING_ENV"
    write_result "Dependency resolution: $DEPENDENCY_STATUS"
    write_result "Release build: $BUILD_STATUS"
    write_result "Swift tests: $TEST_STATUS"
    if [[ ${#VERIFIED_CLI_COMMANDS[@]} -gt 0 ]]; then
        write_result "CLI smoke commands run: $(join_with_comma "${VERIFIED_CLI_COMMANDS[@]}")"
    else
        write_result "CLI smoke commands run: none"
    fi
    write_result "CLI smoke status: $CLI_SMOKE_STATUS"
    write_result "Dashboard smoke: $DASHBOARD_SMOKE_STATUS"
    if [[ ${#VERIFIED_GUARDS[@]} -gt 0 ]]; then
        write_result "Boundary and contract guards: $(join_with_comma "${VERIFIED_GUARDS[@]}")"
    else
        write_result "Boundary and contract guards: $GUARD_STATUS"
    fi
    write_result "Evidence directory: $EVIDENCE_DIR"
    if [[ ${#SKIPPED_PHASES[@]} -gt 0 ]]; then
        write_result "Skipped phases: $(join_with_comma "${SKIPPED_PHASES[@]}")"
    else
        write_result "Skipped phases: none"
    fi
    if [[ -n "$FAILURE_LABEL" ]]; then
        write_result "Failure point: $FAILURE_LABEL"
        write_result "Failure detail: $FAILURE_MESSAGE"
    fi
    write_result ""
    write_result "=== VERDICT: $verdict ==="
    write_result ""
    write_result "Evidence files:"
    write_result "  Environment: $ENVIRONMENT_LOG"
    write_result "  Dependency:  $DEPENDENCY_LOG"
    write_result "  Build log:    $BUILD_LOG"
    write_result "  CLI smoke:    $CLI_SMOKE_LOG"
    write_result "  Test log:     $TEST_LOG"
    write_result "  Summary:      $RESULT_LOG"

    if [[ "$verdict" == "FAIL" ]]; then
        exit 1
    fi
}

mark_failed_phase() {
    local label="$1"

    case "$label" in
        DEPENDENCY_RESOLUTION)
            DEPENDENCY_STATUS="failed"
            ;;
        BUILD)
            BUILD_STATUS="failed"
            ;;
        TEST)
            TEST_STATUS="failed"
            ;;
        CLI_VERSION|CLI_HELP|CLI_STATUS|CLI_DASHBOARD|CLI_SMOKE)
            CLI_SMOKE_STATUS="failed"
            if [[ "$label" == "CLI_DASHBOARD" ]]; then
                DASHBOARD_SMOKE_STATUS="failed"
            fi
            ;;
        REPO_FACTS|CLI_CONTRACT_GUARD|MCP_BOUNDARY_GUARD|ARCHITECTURE_GUARD|EXECUTION_BOUNDARY_GUARD|VISION_CONTRACT_GUARD)
            GUARD_STATUS="failed"
            ;;
    esac
}

fail_step() {
    local label="$1"
    local message="$2"

    mark_failed_phase "$label"
    FAILURE_LABEL="$label"
    FAILURE_MESSAGE="$message"
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
        echo "swift_command=$SWIFT_INVOCATION"
        if [[ -n "$SELECTED_DEVELOPER_DIR" ]]; then
            echo "developer_dir=$SELECTED_DEVELOPER_DIR"
        fi
        if command -v sw_vers >/dev/null 2>&1; then
            echo "sw_vers=$(sw_vers -productVersion)"
        fi
        if "${SWIFT_CMD[@]}" --version >/dev/null 2>&1; then
            echo "swift_version=$("${SWIFT_CMD[@]}" --version | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')"
        fi
        if command -v python3 >/dev/null 2>&1; then
            echo "python_version=$(python3 --version 2>&1)"
        fi
        echo "sanitized_optional_reasoning_env=$SANITIZED_REASONING_ENV"
    } > "$ENVIRONMENT_LOG"
}

require_supported_runtime_platform() {
    local platform
    platform="$(uname -s)"
    write_section "runtime platform"

    if [[ "$platform" != "Darwin" ]]; then
        PLATFORM_STATUS="ineligible ($platform)"
        DEPENDENCY_STATUS="skipped (unsupported platform)"
        BUILD_STATUS="skipped (unsupported platform)"
        TEST_STATUS="skipped (unsupported platform)"
        CLI_SMOKE_STATUS="skipped (unsupported platform)"
        DASHBOARD_SMOKE_STATUS="skipped (unsupported platform)"
        GUARD_STATUS="skipped (unsupported platform)"
        record_skip "dependency resolution, build, CLI smoke, dashboard smoke, tests, and guards skipped because runtime verification is supported on macOS 14+ only"
        fail_step "RUNTIME_PLATFORM" "Unsupported runtime verification platform: $platform. The supported swift build and test path is macOS 14+ only."
    fi

    if command -v sw_vers >/dev/null 2>&1; then
        local product_version
        local major_version
        product_version="$(sw_vers -productVersion)"
        major_version="${product_version%%.*}"
        if [[ "$major_version" =~ ^[0-9]+$ ]] && (( major_version < 14 )); then
            PLATFORM_STATUS="ineligible ($platform $product_version)"
            DEPENDENCY_STATUS="skipped (unsupported platform)"
            BUILD_STATUS="skipped (unsupported platform)"
            TEST_STATUS="skipped (unsupported platform)"
            CLI_SMOKE_STATUS="skipped (unsupported platform)"
            DASHBOARD_SMOKE_STATUS="skipped (unsupported platform)"
            GUARD_STATUS="skipped (unsupported platform)"
            record_skip "dependency resolution, build, CLI smoke, dashboard smoke, tests, and guards skipped because runtime verification is supported on macOS 14+ only"
            fail_step "RUNTIME_PLATFORM" "Unsupported macOS runtime verification version: $product_version. The supported swift build and test path is macOS 14+ only."
        fi
        PLATFORM_STATUS="eligible ($platform $product_version)"
        write_result "RUNTIME_PLATFORM: PASS ($platform $product_version)"
    else
        PLATFORM_STATUS="eligible ($platform)"
        write_result "RUNTIME_PLATFORM: PASS ($platform)"
    fi
    write_result ""
}

run_logged_command() {
    local label="$1"
    local description="$2"
    local log_path="$3"
    shift 3
    local -a pipeline_status=()

    write_section "$description"
    set +e
    env "${SANITIZED_ENV_ARGS[@]}" "$@" 2>&1 | tee "$log_path"
    pipeline_status=("${PIPESTATUS[@]}")
    set -e

    if [[ "${pipeline_status[0]:-1}" -eq 0 ]]; then
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
    local -a pipeline_status=()

    write_section "$description"
    set +e
    env "${SANITIZED_ENV_ARGS[@]}" "$@" 2>&1 | tee -a "$RESULT_LOG"
    pipeline_status=("${PIPESTATUS[@]}")
    set -e

    if [[ "${pipeline_status[0]:-1}" -eq 0 ]]; then
        VERIFIED_GUARDS+=("$description")
        write_result "$label: PASS"
        write_result ""
    else
        fail_step "$label" "Command failed: $description"
    fi
}

mirror_output_file() {
    local source_file="$1"
    local destination_log="$2"

    cat "$source_file" >> "$destination_log"
    cat "$source_file" || true
}

join_with_comma() {
    local joined=""
    local item
    for item in "$@"; do
        if [[ -n "$joined" ]]; then
            joined+=", "
        fi
        joined+="$item"
    done
    echo "$joined"
}

run_cli_smoke() {
    local label="$1"
    local expected_marker="$2"
    shift 2

    local binary="$REPO_ROOT/.build/release/oracle"
    local tmp_output
    tmp_output="$(mktemp)"

    write_section "oracle $*"
    if env "${SANITIZED_ENV_ARGS[@]}" TERM=dumb "$binary" "$@" >"$tmp_output" 2>&1; then
        mirror_output_file "$tmp_output" "$CLI_SMOKE_LOG"
        if ! grep -Fq "$expected_marker" "$tmp_output"; then
            rm -f "$tmp_output"
            fail_step "$label" "CLI smoke output for 'oracle $*' did not contain expected marker: $expected_marker"
        fi
        VERIFIED_CLI_COMMANDS+=("oracle $*")
        write_result "$label: PASS"
        write_result ""
    else
        mirror_output_file "$tmp_output" "$CLI_SMOKE_LOG"
        rm -f "$tmp_output"
        fail_step "$label" "Command failed: oracle $*"
    fi

    rm -f "$tmp_output"
}

run_cli_smokes() {
    local binary="$REPO_ROOT/.build/release/oracle"
    if [[ ! -x "$binary" ]]; then
        fail_step "CLI_SMOKE" "Built oracle binary not found at $binary"
    fi

    run_cli_smoke "CLI_VERSION" "Oracle OS v" version
    run_cli_smoke "CLI_HELP" "Usage: oracle <command>" help
    run_cli_smoke "CLI_STATUS" "Status:" status
    run_cli_smoke "CLI_DASHBOARD" "Agent Dashboard" dashboard
    CLI_SMOKE_STATUS="verified"
    DASHBOARD_SMOKE_STATUS="verified (oracle dashboard -> Agent Dashboard)"
}

echo "=== Oracle OS Verify Build ===" | tee -a "$RESULT_LOG"
echo "Repo:    $REPO_ROOT" | tee -a "$RESULT_LOG"
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$RESULT_LOG"
echo "Mode:    $MODE" | tee -a "$RESULT_LOG"
echo "" | tee -a "$RESULT_LOG"

initialize_sanitized_environment
configure_swift_toolchain
record_environment
write_result "Environment: $ENVIRONMENT_LOG"
write_result "Sanitized optional reasoning env: $SANITIZED_REASONING_ENV"
write_result "Swift command: $SWIFT_INVOCATION"
write_result ""
require_supported_runtime_platform

run_logged_command "DEPENDENCY_RESOLUTION" "$SWIFT_INVOCATION package resolve" "$DEPENDENCY_LOG" "${SWIFT_CMD[@]}" package resolve
DID_RESOLVE=1
DEPENDENCY_STATUS="verified"

# --- Build ---
if [[ "$MODE" == "all" || "$MODE" == "build" ]]; then
    run_logged_command "BUILD" "$SWIFT_INVOCATION build -c release" "$BUILD_LOG" "${SWIFT_CMD[@]}" build -c release
    DID_BUILD=1
    BUILD_STATUS="verified"
    run_cli_smokes
else
    BUILD_STATUS="skipped by mode ($MODE)"
    CLI_SMOKE_STATUS="skipped by mode ($MODE)"
    DASHBOARD_SMOKE_STATUS="skipped by mode ($MODE)"
    record_skip "release build, CLI smoke, and dashboard smoke skipped by mode ($MODE)"
fi

# --- Test ---
if [[ "$MODE" == "all" || "$MODE" == "test" ]]; then
    run_logged_command "TEST" "$SWIFT_INVOCATION test" "$TEST_LOG" "${SWIFT_CMD[@]}" test
    DID_TEST=1
    TEST_STATUS="verified"
else
    TEST_STATUS="skipped by mode ($MODE)"
    record_skip "swift tests skipped by mode ($MODE)"
fi

# --- Boundary guards ---
if [[ "$MODE" == "all" ]]; then
    run_guard_command "REPO_FACTS" "generate_repo_facts.py --check" python3 "$REPO_ROOT/scripts/generate_repo_facts.py" --check
    run_guard_command "CLI_CONTRACT_GUARD" "cli_contract_guard.py" python3 "$REPO_ROOT/scripts/cli_contract_guard.py"
    run_guard_command "MCP_BOUNDARY_GUARD" "mcp_boundary_guard.py" python3 "$REPO_ROOT/scripts/mcp_boundary_guard.py"
    run_guard_command "ARCHITECTURE_GUARD" "architecture_guard.py" python3 "$REPO_ROOT/scripts/architecture_guard.py"
    run_guard_command "EXECUTION_BOUNDARY_GUARD" "execution_boundary_guard.py" python3 "$REPO_ROOT/scripts/execution_boundary_guard.py"
    run_guard_command "VISION_CONTRACT_GUARD" "vision_contract_guard.py" python3 "$REPO_ROOT/scripts/vision_contract_guard.py"
    GUARD_STATUS="verified"
else
    GUARD_STATUS="skipped by mode ($MODE)"
    record_skip "boundary and contract guards skipped by mode ($MODE)"
fi

complete_verification "PASS"
