# Tools Quarantine — Legacy Repair Artifacts

This directory contains historical repair scripts, patch files, throwaway tests, and stale logs
that accumulated during the rebuild phases. None of these files are part of the product.

They are retained here temporarily to preserve context during the Phase 6 consolidation audit.

After the audit is complete and the build is verified clean, delete this directory entirely.

## Contents

- `fix_*.py` — Ad-hoc Python scripts used to patch source files during rebuild.
- `patch_*.py / patch_*.swift` — One-off patch scripts; not part of any maintained workflow.
- `*.swift` (test.swift, fix.swift, etc.) — Throwaway Swift test files not in the test suite.
- `*.log` — Stale compile and build logs. Do not rely on for current system state.
- `*.txt` (COMMIT_MESSAGE, FINAL_HANDOFF, etc.) — Internal rebuild bookkeeping; not product docs.

## Rule

Nothing in this directory is referenced by `Package.swift`, `Sources/`, or `Tests/`.
If you find a reference, that is a bug to fix, not a reason to keep the file here.
