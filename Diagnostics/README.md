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
`.github/workflows/ci.yml` publishes that same directory as the
`canonical-verify-evidence` CI artifact. When full Xcode is installed the
verifier auto-prefers `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
and runs the SwiftPM steps through `xcrun`. The underlying core commands on that
proof path are:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build -c release
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```
