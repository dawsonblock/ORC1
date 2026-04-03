# Release Checklist

Use this checklist before tagging any release. Complete every item in order.

---

## Pre-Release

### Build & Tests
- [ ] `swift build` succeeds with zero errors
- [ ] `swift test` passes (all targets)
- [ ] `python3 scripts/mcp_boundary_guard.py` exits 0 (all 30 MCP tools have dispatch entries)
- [ ] `python3 scripts/architecture_guard.py` exits 0 (no architectural violations)
- [ ] `python3 scripts/execution_boundary_guard.py` exits 0

### Code Quality
- [ ] No `private` func/struct that should be `internal` when split across files
- [ ] No `@Observable` var properties left in extensions (must be in main class body)
- [ ] All `VerifiedExecutor` call sites include a `// VERIFIED:` comment with rationale
- [ ] No new MCP tool added without a dispatch entry in `MCPDispatch.swift`
- [ ] Vision sidecar `endpoints.py` schema matches `VisionSidecarContract.swift` types

### Documentation
- [ ] `ARCHITECTURE.md` reflects any new module or file splits
- [ ] `ORACLE-MCP.md` lists all 30 tool signatures (update if tools changed)
- [ ] `docs/runtime_invariants.md` is current
- [ ] `REPAIR_SUMMARY.md` updated (if repair pass was done)

### Security
- [ ] No secrets, tokens, or credentials committed
- [ ] All localhost-only services bound to `127.0.0.1` (not `0.0.0.0`)
- [ ] `frogbot-scan.yml` / `apisec-scan.yml` passed on latest commit
- [ ] `codeql.yml` scan passed

---

## Release

### Versioning
- [ ] Version string updated in `AppResources/OracleController/Info.plist`
- [ ] Release notes updated in `AppResources/OracleController/ReleaseNotes.md`

### Tagging
```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z
```

### Distribution
- [ ] `scripts/build-release.sh` run successfully
- [ ] `.dmg` created via `scripts/create-controller-dmg.sh`
- [ ] Notarization via `scripts/notarize-controller-release.sh` verified (exit 0)

---

## Post-Release
- [ ] GitHub Release created with release notes and `.dmg` attached
- [ ] `ProjectMemory/roadmap-state.md` updated with release milestone
- [ ] Any known regressions added to `ProjectMemory/risk-register.md`
