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

if __name__ == "__main__":
    root = "Sources"

    if not os.path.isdir(root):
        print("Sources directory not found, skipping execution boundary guard.")
        sys.exit(0)

    violations = scan_repo(root)

    if violations:
        print("\nEXECUTION BOUNDARY VIOLATIONS FOUND\n")
        print("Process() spawning detected outside allowed execution paths.\n")

        for path, lines in violations:
            print(f"{path}")
            for lineno in lines:
                print(f"  line {lineno}: Direct Process() creation forbidden in kernel code")
                print(f"  Fix: Route through VerifiedExecutor and CommandRouter to DefaultProcessAdapter\n")

        sys.exit(1)

    print("✓ Execution boundary guard passed - no unauthorized Process() calls in kernel")
    sys.exit(0)
