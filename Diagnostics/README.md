# Diagnostics

This directory holds archived build and test log snapshots collected during development.

## Status of archived logs

### `archive/invalid-host/runtime_baseline_36_build.log` / `archive/invalid-host/runtime_baseline_36_test.log`

**INVALID CAPTURES — NOT valid proof of a passing baseline.**

Both files contain only:

```text
bash: line 1: swift: command not found
```

The snapshot script ran in an environment where `swift` was not on PATH.
No build output and no test output were captured. These files were moved
under `archive/invalid-host/` so they cannot be mistaken for current proof.
They remain only for historical traceability of the failed capture attempt.

**Authoritative verification path:** re-run validation locally in a supported
Swift environment. Use `bash scripts/verify-build.sh` for the repo-standard
capture. It writes current evidence to `local/verify/latest/`, and
`.github/workflows/ci.yml` publishes that same directory as the shared CI
artifact. The underlying core commands remain:

```sh
swift build -c release
swift test
```
