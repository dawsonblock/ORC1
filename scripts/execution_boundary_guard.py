#!/usr/bin/env python3
"""Execution boundary guard for Oracle-OS.

Scans Swift source files for direct Process() spawning that violates
the execution boundary rules. Runtime code should never directly spawn
processes; all process execution must route through VerifiedExecutor and
CommandRouter to DefaultProcessAdapter.

Allowed Process() usage:
- Sources/OracleOS/Execution/DefaultProcessAdapter*.swift
    (execution router)
- Sources/oracle/SetupWizard.swift
    (tooling, marked TOOLING_ONLY_DIRECT_PROCESS)
- Sources/oracle/Doctor.swift
    (tooling, marked TOOLING_ONLY_DIRECT_PROCESS)
- Test code (mocks and governance tests)

Forbidden:
- Process() anywhere in runtime kernel
    (Sources/OracleOS/* except DefaultProcessAdapter)
- Process() in planning code
- Process() in state management
- Process() in event coordination
"""

import os
import re
import sys
from typing import Optional

# Files allowed to directly spawn processes
ALLOWED_PROCESS_FILES = {
    "DefaultProcessAdapter.swift",
    "DefaultProcessAdapter+Daemon.swift",
    "SetupWizard.swift",
    "Doctor.swift",
    "ProcessShadow.swift",
}

# Directories where Process() is allowed (adapter layer)
ALLOWED_PROCESS_DIRS = [
    "Sources/OracleOS/Execution",
    "Sources/oracle",  # CLI tooling
    "Tests",  # Test code
]

# Directories where Process() is FORBIDDEN (kernel integrity)
FORBIDDEN_PROCESS_DIRS = [
    "Sources/OracleOS/Runtime",
    "Sources/OracleOS/Planning",
    "Sources/OracleOS/State",
    "Sources/OracleOS/Events",
    "Sources/OracleOS/Core",
    "Sources/OracleOS/Memory",
]


# Structural execution-boundary rules for the supported runtime path.
BOUNDARY_CONTRACT_RULES = {
    "Sources/OracleOS/Execution/VerifiedExecutor.swift": {
        "required": [
            (
                "commandRouter.execute(",
                "VerifiedExecutor must route verified commands "
                "through CommandRouter",
            ),
        ],
        "forbidden": [
            (
                "commitCoordinator.commit(",
                "VerifiedExecutor must not own committed-state mutation",
            ),
        ],
    },
    "Sources/OracleOS/Execution/Routing/CommandRouter.swift": {
        "required": [
            (
                "uiRouter.execute(",
                "CommandRouter must continue routing UI commands "
                "through UIRouter",
            ),
            (
                "codeRouter.execute(",
                "CommandRouter must continue routing code commands "
                "through CodeRouter",
            ),
        ],
        "forbidden": [
            (
                "commitCoordinator.commit(",
                "CommandRouter must not own committed-state mutation",
            ),
        ],
    },
    "Sources/OracleOS/Runtime/RuntimeOrchestrator.swift": {
        "required": [
            (
                "container.executor.execute(",
                "RuntimeOrchestrator must continue using "
                "VerifiedExecutor on the supported path",
            ),
            (
                "container.commitCoordinator.commit(",
                "RuntimeOrchestrator must continue handing durable mutation "
                "to CommitCoordinator",
            ),
        ],
    },
    "Sources/OracleOS/Events/CommitCoordinator.swift": {
        "required": [
            (
                "public actor CommitCoordinator",
                "CommitCoordinator must remain the centralized "
                "committed-state authority",
            ),
            (
                "public func commit(",
                "CommitCoordinator must continue exposing the supported "
                "commit entrypoint",
            ),
        ],
    },
    "Sources/OracleOS/MCP/MCPDispatch.swift": {
        "required": [
            (
                "toolName == MCPToolName.experimentSearch",
                "MCPDispatch must keep experiment search as an explicit "
                "exception branch",
            ),
            (
                "handleExperimentSearch(request)",
                "MCPDispatch must keep experiment search on its explicit "
                "async handler path",
            ),
            (
                "bootstrapped.container.experimentManager.run(spec: spec)",
                "Experiment search must remain sandboxed through "
                "ExperimentManager",
            ),
        ],
    },
    "Sources/oracle/Doctor.swift": {
        "required": [
            (
                "EXECUTION AUTHORITY NOTE",
                "Doctor must continue documenting its tooling-only "
                "exception status",
            ),
        ],
    },
    "Sources/oracle/SetupWizard.swift": {
        "required": [
            (
                "EXECUTION AUTHORITY NOTE",
                "SetupWizard must continue documenting its tooling-only "
                "exception status",
            ),
        ],
    },
}


def is_in_allowed_dir(filepath):
    """Check if file is in an allowed directory."""
    for allowed_dir in ALLOWED_PROCESS_DIRS:
        if filepath.startswith(allowed_dir):
            return True
    return False


def is_in_forbidden_dir(filepath):
    """Check if file is in a forbidden directory."""
    for forbidden_dir in FORBIDDEN_PROCESS_DIRS:
        if filepath.startswith(forbidden_dir):
            return True
    return False


def is_allowed_file(filepath):
    """Check if file is explicitly allowed."""
    basename = os.path.basename(filepath)
    return basename in ALLOWED_PROCESS_FILES


def scan_file(path):
    """Scan a Swift file for forbidden Process() usage."""
    with open(path) as f:
        lines = f.readlines()

    violations = []

    # Skip files not in Sources
    if not path.startswith("Sources/"):
        return violations

    # Skip allowed files
    if is_allowed_file(path):
        return violations

    # Skip allowed directories
    if is_in_allowed_dir(path):
        return violations

    # Check forbidden directories only
    if not is_in_forbidden_dir(path):
        return violations

    # Scan for Process() creation
    for lineno, line in enumerate(lines, 1):
        stripped = line.lstrip()
        # Skip comments
        if stripped.startswith("//"):
            continue
        # Look for Process() or Foundation.Process()
        if re.search(r'\bProcess\s*\(\)', line):
            violations.append(lineno)

    return violations


def scan_repo(root):
    """Scan entire repo for violations."""
    violations = []

    for dirpath, _, files in os.walk(root):
        for file in files:
            if file.endswith(".swift"):
                path = os.path.join(dirpath, file)
                v = scan_file(path)

                if v:
                    violations.append((path, v))

    return violations


def scan_boundary_contract_files() -> list:
    violations = []

    for path, rule in BOUNDARY_CONTRACT_RULES.items():
        if not os.path.exists(path):
            violations.append((path, [(0, "required file missing")]))
            continue

        with open(path, encoding="utf-8") as fh:
            content = fh.read()

        issues = []
        for pattern, message in rule.get("required", []):
            if pattern not in content:
                issues.append(
                    (0, f"missing required marker '{pattern}': {message}")
                )

        for pattern, message in rule.get("forbidden", []):
            if pattern in content:
                issues.append((0, f"forbidden marker '{pattern}': {message}"))

        if issues:
            violations.append((path, issues))

    return violations


# ---------------------------------------------------------------------------
# Persistence boundary check
# ---------------------------------------------------------------------------

# Files with explicit authority to mutate disk state.
#
# This list is intentionally exact-path and fail-closed. Broad namespace-level
# allowlists hide boundary drift and make it too easy for new write surfaces to
# appear without review.
ALLOWED_WRITE_AUTHORITIES = {
    "Sources/OracleOS/Common/OracleProductPaths.swift": (
        "bootstrap Oracle-owned directories under .oracle/ "
        "and app support"
    ),
    "Sources/OracleOS/Common/Diagnostics/DiagnosticsWriter.swift": (
        "persist runtime diagnostics snapshots"
    ),
    "Sources/OracleOS/Common/Diagnostics/MetricsRecorder.swift": (
        "persist runtime performance metrics"
    ),
    "Sources/OracleOS/Common/Diagnostics/StrategyDiagnostics.swift": (
        "persist strategy selection diagnostics"
    ),
    "Sources/OracleOS/Events/FileEventStore.swift": (
        "append durable event log entries"
    ),
    "Sources/OracleOS/Events/Commit/CommitWAL.swift": (
        "persist commit write-ahead log for crash recovery"
    ),
    "Sources/OracleOS/Intent/Policies/ApprovalStore.swift": (
        "persist approval requests, receipts, and controller heartbeat"
    ),
    "Sources/OracleOS/Learning/ExperienceStore.swift": (
        "append execution traces to session JSONL files"
    ),
    "Sources/OracleOS/Learning/Recipes/RecipeStore.swift": (
        "persist user-owned recipe definitions"
    ),
    "Sources/OracleOS/Learning/Project/ProjectMemoryIndexer.swift": (
        "own SQLite project-memory index"
    ),
    "Sources/OracleOS/Learning/Project/ProjectMemoryStore.swift": (
        "persist project memory drafts and residue artifacts"
    ),
    "Sources/OracleOS/Learning/Trace/FailureArtifactWriter.swift": (
        "persist trace failure artifacts and screenshots"
    ),
    "Sources/OracleOS/Planning/Workflows/WorkflowIndex.swift": (
        "persist workflow plan cache"
    ),
    "Sources/OracleOS/Code/Execution/WorkspaceRunner.swift": (
        "apply scoped workspace mutations requested by the "
        "verified execution path"
    ),
    "Sources/OracleOS/Code/Intelligence/RepositoryIndexer.swift": (
        "persist repository index cache under .oracle"
    ),
    "Sources/OracleOS/WorldModel/Graph/GraphPersistence.swift": (
        "own SQLite world-model graph persistence"
    ),
    "Sources/OracleOS/Execution/Experiments/ExperimentManager.swift": (
        "persist experiment result metadata under sandbox-only "
        "oracle state"
    ),
    "Sources/OracleOS/Execution/Experiments/WorktreeSandbox.swift": (
        "mutate isolated experiment worktrees only"
    ),
}

_WRITE_PATTERNS = [
    (
        "FileManager.createDirectory",
        re.compile(r'\bFileManager\b.*\bcreateDirectory\b'),
    ),
    ("FileManager.createFile", re.compile(r'\bFileManager\b.*\bcreateFile\b')),
    ("FileManager.copyItem", re.compile(r'\bFileManager\b.*\bcopyItem\b')),
    ("FileManager.moveItem", re.compile(r'\bFileManager\b.*\bmoveItem\b')),
    ("FileManager.removeItem", re.compile(r'\bFileManager\b.*\bremoveItem\b')),
    (
        "FileHandle(forWritingTo:)",
        re.compile(r'\bFileHandle\s*\(\s*forWritingTo\s*:'),
    ),
    (
        "FileHandle(forUpdating:)",
        re.compile(r'\bFileHandle\s*\(\s*forUpdating\s*:'),
    ),
    ("write(to:)", re.compile(r'\.write\(to:')),
    ("write(toFile:)", re.compile(r'\.write\(toFile:')),
    ("sqlite3_open", re.compile(r'\bsqlite3_open(?:_v2)?\s*\(')),
]


def _write_authority(filepath: str) -> Optional[str]:
    return ALLOWED_WRITE_AUTHORITIES.get(filepath)


def validate_allowed_write_authorities() -> list[str]:
    missing = []
    for path in sorted(ALLOWED_WRITE_AUTHORITIES):
        if not os.path.exists(path):
            missing.append(path)
    return missing


def scan_file_for_writes(path: str) -> list:
    """Return list of (lineno, pattern_desc) for disallowed file writes."""
    if not path.startswith("Sources/OracleOS/"):
        return []
    if _write_authority(path) is not None:
        return []
    violations_out = []
    with open(path, encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            stripped = line.lstrip()
            if stripped.startswith("//"):
                continue
            for description, pattern in _WRITE_PATTERNS:
                if pattern.search(line):
                    violations_out.append((lineno, description))
                    break
    return violations_out


def scan_repo_for_writes(root: str) -> list:
    results = []
    for dirpath, _, files in os.walk(root):
        for fname in files:
            if fname.endswith(".swift"):
                p = os.path.join(dirpath, fname)
                v = scan_file_for_writes(p)
                if v:
                    results.append((p, v))
    return results


if __name__ == "__main__":
    root = "Sources"

    if not os.path.isdir(root):
        print(
            "Sources directory not found, "
            "skipping execution boundary guard."
        )
        sys.exit(0)

    exit_code = 0

    violations = scan_repo(root)
    if violations:
        print("\nEXECUTION BOUNDARY VIOLATIONS FOUND\n")
        print("Process() spawning detected outside allowed execution paths.\n")
        for path, lines in violations:
            print(f"{path}")
            for lineno in lines:
                print(
                    f"  line {lineno}: "
                    "Direct Process() creation forbidden in kernel code"
                )
                print(
                    "  Fix: Route through VerifiedExecutor and "
                    "CommandRouter to DefaultProcessAdapter\n"
                )
        exit_code = 1
    else:
        print(
            "✓ Process boundary guard passed - "
            "no unauthorized Process() calls in kernel"
        )

    missing_write_authorities = validate_allowed_write_authorities()
    if missing_write_authorities:
        print("\nEXECUTION BOUNDARY GUARD MISCONFIGURED\n")
        print("Configured write-authority files are missing from the repo.\n")
        for path in missing_write_authorities:
            print(f"  missing: {path}")
        exit_code = 1

    write_violations = scan_repo_for_writes(root)
    if write_violations:
        print("\nPERSISTENCE BOUNDARY VIOLATIONS FOUND\n")
        print(
            "File-write patterns detected outside explicitly "
            "approved persistence authorities.\n"
        )
        for path, items in write_violations:
            print(f"{path}")
            for lineno, pattern in items:
                print(
                    f"  line {lineno}: write primitive ({pattern}) "
                    "outside explicit write authority"
                )
                print(
                    "  Fix: move the write into an approved "
                    "store/authority file or add a narrowly "
                    "justified authority entry.\n"
                )
        exit_code = 1
    else:
        print(
            "✓ Persistence boundary guard passed - "
            "file writes confined to explicit authority owners"
        )

    boundary_violations = scan_boundary_contract_files()
    if boundary_violations:
        print("\nMAIN-PATH EXECUTION CONTRACT VIOLATIONS FOUND\n")
        print(
            "main-path execution boundary drifted; update code and "
            "contract together or route new behavior through the "
            "verified spine.\n"
        )
        for path, items in boundary_violations:
            print(f"{path}")
            for lineno, message in items:
                if lineno > 0:
                    print(f"  line {lineno}: {message}")
                else:
                    print(f"  issue: {message}")
            print("")
        exit_code = 1
    else:
        print(
            "✓ Main-path execution contract guard passed - "
            "verified spine and documented exceptions remain explicit"
        )

    sys.exit(exit_code)
