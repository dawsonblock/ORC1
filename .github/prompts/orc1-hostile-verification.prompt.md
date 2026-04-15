---
description: "Hostile re-audit for the repaired ORC1 upload: verify that the remaining-gap repair actually landed, close only narrow contradictions, and lower claims when evidence is insufficient."
name: "Run ORC1 Hostile Verification"
argument-hint: "Optional repaired-upload area to emphasize: script drift, controller proof, path drift, crash-style guardrails, CI truth, or docs-to-reality drift."
agent: "ORC1 Repo Hardening"
---

Use the ORC1 Repo Hardening agent for the hostile re-audit pass in this repository.

You are working inside the repaired latest ORC1 repository.

This pass is not a general implementation pass.
This pass is a hostile re-audit.

Your job is to verify that the remaining-gap repair was actually completed, find anything still inconsistent or misleading, and apply only narrow follow-up fixes required to make the repo truthful and internally consistent.

Do not do a rewrite.
Do not broaden scope.
Do not add speculative features.
Do not refactor healthy code just to make it prettier.
Do not assume the prior repair succeeded just because files changed.

Read the repo again from the repaired state.
Trust code, scripts, workflows, packaging behavior, runtime paths, and tests over comments or prior summaries.
If docs disagree with code, fix one so they match.
If multiple files describe different supported workflows, resolve the contradiction.

## Mission

Prove that the repository now tells one consistent story across:

- build
- verification
- release
- supported surfaces
- optional/demo surfaces
- runtime failure handling
- CI proof

You are checking whether the latest repair actually fixed these exact unresolved areas:

1. `scripts/build-release.sh` no longer depends on guessed `.build/$CONFIG/oracle`
2. all build-related scripts now share one toolchain/bootstrap path
3. controller-side behavioral proof is materially stronger
4. `.build/...` assumptions are no longer part of the canonical supported path
5. runtime-reachable crash-style guardrails were reduced or justified
6. docs, scripts, and CI now describe the same bounded product

## Global rules

1. Proof over implementation intent
   Do not reward code for trying.
   Only accept what is actually enforced by scripts, tests, workflows, and runtime behavior.
2. Keep the architecture intact
   No re-platforming.
   No product redesign.
3. Prefer simplification over duplication
   If the repair introduced duplicate helpers, repeated bootstrap code, overlapping docs, or competing truth sources, collapse them.
4. Lower claims instead of hand-waving gaps
   If support is narrower than docs suggest, shrink the claim.
   Do not stretch evidence.
5. Fix only what this audit proves is still wrong
   This is not a feature pass.

## Audit procedure

### Phase 1 - build/release consistency audit

Inspect:

- `scripts/verify-build.sh`
- `scripts/build-controller-app.sh`
- `scripts/build-release.sh`
- any shared bootstrap/helper script introduced by the repair
- `Package.swift`
- any docs or workflows invoking those scripts

Verify:

- all build/release scripts now use the same toolchain/bootstrap logic
- `DEVELOPER_DIR` handling is consistent
- Swift invocation strategy is consistent and deliberate
- `build-release.sh` resolves binaries through authoritative path discovery
- no critical packaging step still depends on guessed SwiftPM layout
- the canonical build, verify, and release paths are now clearly identifiable

If any script still diverges, fix it.

### Phase 2 - controller-proof audit

Inspect controller-related tests and runtime edges.

Verify that controller-side proof is now behavioral, not cosmetic.

Specifically look for proof around:

- controller startup
- host/helper resolution precedence
- missing helper failure behavior
- invalid helper path behavior
- host launch / readiness / handshake behavior
- packaged controller smoke behavior if present
- user-visible boundary failures that would matter in real use

Reject shallow tests that only construct objects or mirror static data.
Strengthen weak proof where needed, but keep it tight and high value.

### Phase 3 - path-drift audit

Search for remaining `.build/...` assumptions across:

- docs
- scripts
- source
- tests
- workflows

Classify each occurrence:

- canonical supported path
- development override
- fallback for local development
- stale/misleading leftover

Requirements:

- canonical supported flows must not depend on raw `.build/...` assumptions
- dev-only fallbacks must be clearly lower precedence and clearly labeled
- stale misleading path guidance must be removed or corrected

Pay special attention to:

- `README.md`
- controller docs
- release docs
- `HostProcessClient` or equivalent helper resolution code
- workflow examples and smoke commands

### Phase 4 - runtime failure audit

Search for:

- `fatalError`
- `assertionFailure`
- `preconditionFailure`
- force unwraps
- `"unreachable"` branches
- hidden fallback behavior

For each occurrence in runtime-relevant code:

- prove it is structurally impossible by construction, or
- replace it with explicit typed/runtime failure if reachable from real input, packaging drift, operator action, or version mismatch

Pay special attention to:

- `Sources/OracleOS/Runtime/RuntimeContext.swift`
- `Sources/OracleOS/TaskLedger/TaskLedger.swift`
- `Sources/OracleOS/MCP/MCPTools.swift`

Do not weaken invariants.
Do not convert failures into silent ignores.

### Phase 5 - CI truth audit

Inspect:

- `.github/workflows/ci.yml`
- `.github/workflows/controller-release.yml`
- `.github/workflows/architecture.yml`
- all other workflows

Classify each workflow as:

- canonical product proof
- canonical release proof
- supplemental architecture guardrail
- supplemental security/scanner
- stale/noise

Verify:

- workflow names and docs do not overstate proof
- canonical workflows match the documented supported paths
- supplemental scanners do not masquerade as runtime certification
- stale workflows are removed, disabled, or clearly noncanonical

### Phase 6 - docs-to-reality audit

Re-read:

- `README.md`
- `docs/PRODUCT_CONTRACT.md`
- `STATUS.md`
- `docs/RELEASE_READY_SUMMARY.md`
- controller docs
- release/build docs

Verify they all agree on:

- canonical build path
- canonical verify path
- canonical release path
- supported product surfaces
- optional/experimental surfaces
- platform assumptions
- what CI proves
- what remains external or dev-only

If the docs still overclaim, lower them.
If the code is stronger than the docs, update carefully without exaggeration.

## Required deliverables

Make any narrow follow-up fixes directly in the repo.

Then produce:

1. Re-audit report
   State:
   - what was checked
   - what passed
   - what failed
   - what you changed during this hostile pass
2. Canonical truth summary
   State exactly:
   - single build path
   - single verification path
   - single release path
   - supported surfaces
   - optional/experimental/demo surfaces
3. Remaining honesty gaps
   List anything that still cannot be claimed as fully hardened or production-grade and why.
4. Evidence list
   Reference the exact scripts, tests, workflows, and docs that now support the repo's claims.

## Decision rule

If there is doubt, do not approve the stronger claim.
Lower the claim instead.

## Definition of done

The work is done when:

- the repaired repo survives a hostile re-audit
- no critical script still depends on guessed artifact layout
- controller-side proof is meaningfully stronger
- `.build/...` assumptions are not part of the canonical supported story
- runtime crash-style failures are either justified or reduced
- docs, scripts, workflows, and tests now describe the same bounded product
