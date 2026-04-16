# Release Readiness Summary

**Date:** 2026-04-16  
**Branch:** `main`  
**Status:** Verifier-clean on the canonical source proof path; unsigned controller packaging preview is a local and CI-supported path, and signed/notarized controller proof now has a dedicated GitHub Actions release path that remains credential-dependent until it succeeds.

## Current Verification State

- `bash scripts/verify-build.sh` returns `=== VERDICT: PASS ===` on the supported macOS proof path.
- The current evidence shows dependency resolution, release build, non-interactive CLI smokes, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test`, and all bundled guard steps passing in one canonical invocation.
- `bash scripts/verify-build.sh --build-only` also returns `=== VERDICT: PASS ===` on the same proof path.
- Separate focused guard runs remain useful for iteration, but they are no longer standing in for a failing end-to-end verifier.
- Current proof artifacts are written to `local/verify/latest/`.

## Release Gate

- The canonical verifier is green again; do not treat that as full release packaging proof by itself.
- Use `docs/RELEASE_CHECKLIST.md` before tagging a release, and treat `.github/workflows/controller-release.yml` `workflow_dispatch` with `signed_proof=true` or a tagged `release` run as the shared signed/notarized controller proof surface.
- Use `AppResources/OracleController/ReleaseNotes.md` for packaged-controller release notes.

## Residual Notes

- The supported local proof path now auto-prefers `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` via `xcrun` when full Xcode is installed.
- Release packaging and controller packaging now share the same Swift bootstrap helper as the canonical verifier, resolve built products through SwiftPM's reported bin path, and emit packaging proof logs under `dist/controller-release-proof/`.
- `.github/workflows/ci.yml` remains the canonical shared proof surface; `architecture.yml` and `controller-release.yml` remain supplemental enforcement and packaging workflows.
- `web/` remains demo/dev scaffolding and is not part of the supported operator contract.
- `vision-sidecar/` remains optional and experimental.
