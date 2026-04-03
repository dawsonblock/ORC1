# Diagnostics

This directory holds build and test log snapshots collected during development.

## Status of archived logs

### `runtime_baseline_36_build.log` / `runtime_baseline_36_test.log`

**INVALID CAPTURES — NOT valid proof of a passing baseline.**

Both files contain only:

```
bash: line 1: swift: command not found
```

The snapshot script ran in an environment where `swift` was not on PATH.
No build output and no test output were captured. These files are retained
for historical traceability of the capture attempt but do not certify
anything about the codebase.

**Authoritative baseline:** 646 tests in 94 suites passing as of ORC1-main-7.
Reproduce locally with:

```sh
swift test 2>&1 | tail -5
```
