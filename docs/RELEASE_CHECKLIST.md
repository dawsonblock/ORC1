# Release Checklist

Use this checklist before tagging any release. Complete every item in order.

---

## Pre-Release

### Build & Tests

- [ ] Canonical verification passed via `bash scripts/verify-build.sh` or the current artifact from `.github/workflows/ci.yml`
- [ ] `swift build` succeeds
- [ ] Any build warnings are reviewed and either fixed or explicitly noted in `STATUS.md` or `BASELINE.md`
- [ ] `swift test` passes (all targets)
- [ ] `python3 scripts/mcp_boundary_guard.py` exits 0 (all 30 MCP tools have dispatch entries)
- [ ] `python3 scripts/architecture_guard.py` exits 0 (no architectural violations)
- [ ] `python3 scripts/execution_boundary_guard.py` exits 0
- [ ] `python3 scripts/vision_contract_guard.py` exits 0 (vision sidecar schema and runtime payload match `VisionSidecarContract.swift`)

`controller-release.yml` is a packaging workflow. It validates unsigned controller app and DMG outputs on PRs and pushes, and it owns the signed/notarized controller proof path through either a tag-triggered release run or `workflow_dispatch` with `signed_proof=true`. It is not the canonical build/test proof path.

### Code Quality

- [ ] No `private` func/struct that should be `internal` when split across files
- [ ] No `@Observable` var properties left in extensions (must be in main class body)
- [ ] No new MCP tool added without a dispatch entry in `MCPDispatch.swift`

### Documentation

- [ ] `ARCHITECTURE.md` reflects any new module or file splits
- [ ] `ORACLE-MCP.md` lists the current live MCP tool signatures (update if tools changed)
- [ ] `docs/runtime_invariants.md` is current
- [ ] `STATUS.md` updated for any contract-significant change

### Security

- [ ] No secrets, tokens, or credentials committed
- [ ] All localhost-only services bound to `127.0.0.1` (not `0.0.0.0`)
- [ ] Canonical verification passed via `bash scripts/verify-build.sh` or the artifact from `.github/workflows/ci.yml`
- [ ] `codeql.yml` scan passed

---

## Release

### Versioning

- [ ] Version string updated in `Sources/OracleOS/Common/Types.swift` (`AppResources/OracleController/Info.plist` is a build-time template)
- [ ] Release notes updated in `AppResources/OracleController/ReleaseNotes.md`

### Tagging

```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z
```

### Distribution

- [ ] CLI/MCP tarball: `scripts/build-release.sh` succeeds (produces `oracle-os-{VERSION}*.tar.gz`)
- [ ] Controller packaging preview: `scripts/create-controller-dmg.sh --configuration release --skip-sign` succeeds locally or the `validate` job in `.github/workflows/controller-release.yml` succeeds
- [ ] Signed/notarized controller proof: `.github/workflows/controller-release.yml` succeeds through `workflow_dispatch` with `signed_proof=true` or a tagged `release` run with `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_DEVELOPER_IDENTITY`, `APPLE_NOTARY_KEY_P8_BASE64`, `APPLE_NOTARY_KEY_ID`, and `APPLE_NOTARY_ISSUER_ID` configured
- [ ] Signed proof evidence reviewed: `dist/controller-release-proof/` locally or the uploaded `oracle-controller-release-proof` artifact contains successful `plutil`, `codesign`, `stapler`, and `spctl` output
- [ ] Controller notarization fallback: `scripts/notarize-controller-release.sh` verified (exit 0) when valid local notary credentials are available

---

## Post-Release

- [ ] GitHub Release created with release notes and `.dmg` attached
- [ ] `ProjectMemory/roadmap-state.md` updated with release milestone
- [ ] Any known regressions added to `ProjectMemory/risk-register.md`
