#!/usr/bin/env python3
"""Execution boundary guard for Oracle-OS.

Scans Swift source files for direct Process() spawning that violates
the execution boundary rules. Runtime code should never directly spawn
processes; all process execution must route through VerifiedExecutor and
CommandRouter to DefaultProcessAdapter.

Allowed Process() usage:
- Sources/OracleOS/Execution/DefaultProcessAdapter*.swift (execution router)
- Sources/oracle/SetupWizard.swift (tooling, marked TOOLING_ONLY_DIRECT_PROCESS)
- Sources/oracle/Doctor.swift (tooling, marked TOOLING_ONLY_DIRECT_PROCESS)
- Test code (mocks and governance tests)

Forbidden:
- Process() anywhere in runtime kernel (Sources/OracleOS/* except DefaultProcessAdapter)
- Process() in planning code
- Process() in state management
- Process() in event coordination
"""

import os
import re
import sys

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

# ---------------------------------------------------------------------------
# Persistence boundary check
# ---------------------------------------------------------------------------

# Directories where Tier-3 file writes (FileManager mutations, Data.write) are
# explicitly allowed.  All other locations are flagged.
ALLOWED_WRITE_DIRS = [
    "Sources/OracleOS/Memory",         # UnifiedMemoryStore, ProjectMemoryStore
    "Sources/OracleOS/Persistence",    # canonical future home
    "Sources/OracleOS/MCP",            # RecipeStore
    "Sources/OracleOS/Planning",       # WorkflowIndex
    "Sources/OracleOS/Learning",       # ExperienceStore
    "Sources/OracleOS/Execution",      # DefaultProcessAdapter (may write temp files)
    "Sources/OracleOS/Code",           # RepositoryIndexer, WorkspaceRunner (approved)
    "Sources/OracleOS/Common",         # DiagnosticsWriter, MetricsRecorder, StrategyDiagnostics
    "Sources/OracleOS/Intent",         # ApprovalStore
    "Sources/OracleOS/Events",         # FileEventStore, CommitWAL
    "Sources/oracle",                  # CLI tooling
    "Sources/OracleController",        # Controller app layer
    "Sources/OracleControllerHost",    # Host layer
    "Sources/OracleControllerShared",  # Shared models
    "Tests",
]

_WRITE_PATTERNS = [
    re.compile(r'\bFileManager\b.*\bcreateFile\b'),
    re.compile(r'\bFileManager\b.*\bcopyItem\b'),
    re.compile(r'\bFileManager\b.*\bmoveItem\b'),
    re.compile(r'\bFileManager\b.*\bremoveItem\b'),
    re.compile(r'\.write\(to:'),
    re.compile(r'\.write\(toFile:'),
]


def _is_allowed_write_dir(filepath: str) -> bool:
    for d in ALLOWED_WRITE_DIRS:
        if filepath.startswith(d):
            return True
    return False


def scan_file_for_writes(path: str) -> list:
    """Return list of (lineno, pattern_desc) for disallowed file writes."""
    if not path.startswith("Sources/OracleOS/"):
        return []
    if _is_allowed_write_dir(path):
        return []
    violations_out = []
    with open(path, encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            stripped = line.lstrip()
            if stripped.startswith("//"):
                continue
            for pat in _WRITE_PATTERNS:
                if pat.search(line):
                    violations_out.append((lineno, pat.pattern))
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
        print("Sources directory not found, skipping execution boundary guard.")
        sys.exit(0)

    exit_code = 0

    violations = scan_repo(root)
    if violations:
        print("\nEXECUTION BOUNDARY VIOLATIONS FOUND\n")
        print("Process() spawning detected outside allowed execution paths.\n")
        for path, lines in violations:
            print(f"{path}")
            for lineno in lines:
                print(f"  line {lineno}: Direct Process() creation forbidden in kernel code")
                print(f"  Fix: Route through VerifiedExecutor and CommandRouter to DefaultProcessAdapter\n")
        exit_code = 1
    else:
        print("✓ Process boundary guard passed - no unauthorized Process() calls in kernel")

    write_violations = scan_repo_for_writes(root)
    if write_violations:
        print("\nPERSISTENCE BOUNDARY VIOLATIONS FOUND\n")
        print("File-write patterns detected outside persistence-designated directories.\n")
        for path, items in write_violations:
            print(f"{path}")
            for lineno, pattern in items:
                print(f"  line {lineno}: Tier-3 write pattern ({pattern}) outside allowed namespace")
                print(f"  Fix: Move write logic into Sources/OracleOS/Persistence/ or the designated store.\n")
        exit_code = 1
    else:
        print("✓ Persistence boundary guard passed - file writes confined to designated namespaces")

    sys.exit(exit_code)
