# Release Readiness Summary

**Date:** 2026-04-13  
**Branch:** `main`  
**Status:** Not release-ready; the canonical verifier currently fails in the Swift test phase.

## Current Verification State

- `bash scripts/verify-build.sh --build-only` returns `=== VERDICT: PASS ===` on the supported macOS proof path.
- `bash scripts/verify-build.sh` currently fails at `TEST` after dependency resolution, release build, and non-interactive CLI smokes pass.
- The failing test command in the current evidence is `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test`.
- Separate guard runs currently pass for repo facts, CLI contract, MCP boundary, architecture, and execution-boundary enforcement.
- Current proof artifacts are written to `local/verify/latest/`.

## Release Gate

- Do not tag a release until `bash scripts/verify-build.sh` returns `=== VERDICT: PASS ===` again.
- Use `docs/RELEASE_CHECKLIST.md` before tagging a release once the canonical verifier is green.
- Use `AppResources/OracleController/ReleaseNotes.md` for packaged-controller release notes.

## Residual Notes

- The supported local proof path now auto-prefers `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` via `xcrun` when full Xcode is installed.
- `web/` remains demo/dev scaffolding and is not part of the supported operator contract.
- `vision-sidecar/` remains optional and experimental.
