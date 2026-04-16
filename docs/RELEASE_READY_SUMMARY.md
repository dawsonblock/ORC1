# Release Readiness Summary

**Date:** 2026-04-14  
**Branch:** `main`  
**Status:** Verifier-clean on the canonical source proof path; release packaging and notarization remain separate release-gate work.

## Current Verification State

- `bash scripts/verify-build.sh` returns `=== VERDICT: PASS ===` on the supported macOS proof path.
- The current evidence shows dependency resolution, release build, non-interactive CLI smokes, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test`, and all bundled guard steps passing in one canonical invocation.
- `bash scripts/verify-build.sh --build-only` also returns `=== VERDICT: PASS ===` on the same proof path.
- Separate focused guard runs remain useful for iteration, but they are no longer standing in for a failing end-to-end verifier.
- Current proof artifacts are written to `local/verify/latest/`.

## Release Gate

- The canonical verifier is green again; do not treat that as full release packaging proof by itself.
- Use `docs/RELEASE_CHECKLIST.md` before tagging a release, and complete the controller packaging/signing/notarization path where applicable.
- Use `AppResources/OracleController/ReleaseNotes.md` for packaged-controller release notes.

## Residual Notes

- The supported local proof path now auto-prefers `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` via `xcrun` when full Xcode is installed.
- Release packaging and controller packaging now share the same Swift bootstrap helper as the canonical verifier and resolve built products through SwiftPM's reported bin path.
- `.github/workflows/ci.yml` remains the canonical shared proof surface; `architecture.yml` and `controller-release.yml` remain supplemental enforcement and packaging workflows.
- `web/` remains demo/dev scaffolding and is not part of the supported operator contract.
- `vision-sidecar/` remains optional and experimental.
