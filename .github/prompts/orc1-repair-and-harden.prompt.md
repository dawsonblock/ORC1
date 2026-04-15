---
description: "Repair prompt for the current ORC1 upload: unify build bootstrap, remove guessed .build artifact paths from canonical flows, strengthen controller-side proof, audit final crash-style guardrails, and align docs and CI to the actual bounded product."
name: "Run ORC1 Repair and Harden"
argument-hint: "Optional current-upload issue to emphasize: shared bootstrap, artifact discovery, controller proof, .build path drift, or runtime guardrail audit."
agent: "ORC1 Repo Hardening"
---

Use the ORC1 Repo Hardening agent for the current-upload repair pass in this repository.

You are working inside the latest extracted ORC1 repository.

Do not do a broad rewrite.
Do not expand scope.
Do not add speculative features.
Do not change the architecture unless a blocker forces a narrow change.
Do not claim production readiness unless code, scripts, tests, workflows, and docs actually prove it.

Read the repository first.
Trust code, manifests, scripts, workflows, runtime paths, packaging behavior, and tests over comments.
If docs disagree with code, fix one so they match.
Do not leave contradictions in place.

## What is already true in this upload

Keep these intact unless a blocker requires adjustment:

- the overall repo shape is coherent
- the product boundary is mostly honest
- supported core is still controller app + MCP server + CLI
- `vision-sidecar/` is optional/experimental, not core
- `web/` is demoted from the supported core
- top-level docs are more aligned than earlier versions
- runtime-core proof is materially stronger than many earlier snapshots

This pass is not about redoing that work.
This pass is about fixing the remaining concrete gaps that still exist in the actual code.

## Current unresolved issues confirmed from this upload

1. `scripts/build-release.sh` still depends on guessed SwiftPM layout
   It still assumes the built CLI binary is at `.build/$CONFIG/oracle`.
   That must be removed.
2. Build-related scripts still do not share one toolchain/bootstrap path
   `scripts/verify-build.sh` uses stricter Apple toolchain bootstrap behavior than:
   - `scripts/build-controller-app.sh`
   - `scripts/build-release.sh`
     That inconsistency must be eliminated.
     Verify, controller build, and release build must use the same toolchain/bootstrap logic.
3. `scripts/verify-build.sh` itself still uses guessed `.build/...` paths for CLI smoke
   The canonical verifier still checks `"$REPO_ROOT/.build/release/oracle"`.
   That must be replaced with authoritative artifact discovery.
4. Controller-side behavioral proof is still too weak
   The runtime core has much stronger proof than the controller boundary.
   Controller-side tests need stronger behavioral coverage around:
   - host resolution precedence
   - missing helper failure handling
   - invalid helper path handling
   - launch/readiness behavior
   - packaged-app or packaging-adjacent smoke where realistic
5. `.build/...` assumptions still survive in docs and development fallbacks
   They may remain as dev-only overrides where necessary, but they must not be part of the canonical supported path and must be clearly labeled as development-only.
6. Crash-style runtime guardrails still need final audit
   The repo still contains runtime-relevant uses of:
   - `fatalError`
   - `assertionFailure`
   - `preconditionFailure`
   - force unwraps
     These need a strict reachability audit.
     Keep only what is truly impossible by construction.
     Replace reachable cases with explicit failures.

## Mission

Make the repo internally consistent enough that its documented build, verify, and release story matches the actual code and scripts.

Do this in order.

### Phase 1 - unify the build bootstrap

Inspect:

- `scripts/verify-build.sh`
- `scripts/build-controller-app.sh`
- `scripts/build-release.sh`

Required outcome:
create one shared shell helper or one shared bootstrap path used by all build-related scripts.

Requirements:

- same `DEVELOPER_DIR` handling
- same Swift invocation strategy
- same Apple toolchain assumptions
- deterministic failure with clear errors if the required toolchain is unavailable
- no duplicated drift-prone bootstrap logic
- no one-off special script behavior

Do not leave verification stricter than release or release looser than verification.
All three scripts must build from the same toolchain truth.

### Phase 2 - remove guessed artifact paths from critical flows

Fix:

- `scripts/build-release.sh`
- `scripts/verify-build.sh`

Requirements:

- stop assuming `.build/$CONFIG/oracle`
- stop assuming `"$REPO_ROOT/.build/release/oracle"` for canonical CLI smoke
- use authoritative artifact discovery such as `swift build --show-bin-path` or an equally reliable resolved-path mechanism
- preserve release output/archive structure where otherwise correct
- preserve clear smoke behavior, but make it path-safe

Then audit the repo for other critical-path `.build/...` assumptions.

Rules for remaining `.build/...` occurrences:

- if part of canonical build/verify/release flow: replace them
- if part of dev-only fallback/override behavior: keep only if clearly marked and lower precedence
- if stale or misleading: remove them

### Phase 3 - strengthen controller-side proof with high-value behavioral tests

Do not pad the suite with cosmetic tests.

Add or improve tests around the controller boundary, especially:

- host helper resolution precedence
- explicit override vs bundled helper vs dev fallback behavior
- missing helper failure behavior
- invalid helper path rejection
- launch/readiness/handshake behavior if testable without broad redesign
- user-visible controller boundary errors that should be stable
- packaging-adjacent smoke if realistic and honest

Guidelines:

- prefer a few integration-style tests over many object-construction tests
- assert real behavior and failure modes
- make sure tests would fail if path resolution or host wiring drifted
- keep controller proof aligned with the actual supported controller contract

### Phase 4 - clean docs and path guidance

Audit:

- `README.md`
- controller docs
- release docs
- product contract docs
- status/release summaries
- any script examples
- controller host discovery code

Required outcome:

- canonical supported flows must not point users at raw `.build/...` binaries
- if `.build/...` examples remain, they must be labeled development-only
- bundled or scripted paths must be presented as the supported path
- docs must distinguish clearly between:
  - supported packaged flow
  - scripted source-build flow
  - developer override/debug flow

Do not erase useful developer workflows.
Just stop presenting them as the canonical product path.

### Phase 5 - final runtime guardrail audit

Audit runtime-relevant uses of:

- `fatalError`
- `assertionFailure`
- `preconditionFailure`
- force unwraps
- unreachable default branches

Pay special attention to:

- `Sources/OracleOS/Runtime/RuntimeContext.swift`
- `Sources/OracleOS/TaskLedger/TaskLedger.swift`
- `Sources/OracleOS/MCP/MCPTools.swift`

For each occurrence:

- determine whether it is truly impossible by construction
- if truly impossible, keep only with justified invariant meaning
- if reachable from real input, packaging drift, operator action, or version mismatch, replace with explicit typed/runtime failure

Do not weaken invariants.
Convert hidden fragility into explicit behavior.

### Phase 6 - align CI and truth documents after the repair

Re-check:

- `.github/workflows/ci.yml`
- `.github/workflows/controller-release.yml`
- `.github/workflows/architecture.yml`
- `README.md`
- `docs/PRODUCT_CONTRACT.md`
- `STATUS.md`
- `docs/RELEASE_READY_SUMMARY.md`

Make sure these all state the same bounded reality:

- canonical build path
- canonical verification path
- canonical release path
- supported core surfaces
- optional/experimental surfaces
- what CI proves
- what remains platform-specific
- what remains dev-only

Do not raise claims beyond evidence.

## Deliverables

Make the code and doc changes directly in the repo.

Then produce:

1. Repair summary
   State:
   - what remained broken in this upload
   - what you changed
   - what you intentionally left unchanged
2. Proof summary
   State:
   - which scripts now share the bootstrap/toolchain logic
   - how canonical artifact discovery now works
   - which controller-side behavioral tests were added or strengthened
   - which docs were corrected
3. Remaining risk list
   State any remaining narrow risks, especially:
   - macOS-only assumptions
   - optional sidecar dependencies
   - dev-only fallback paths retained by design
   - anything still not proven by tests

## Constraints

Do not:

- rewrite the system
- add unrelated features
- add new product surfaces
- leave critical script drift unresolved
- leave canonical paths dependent on guessed `.build/...` layout
- claim certification unless the repo proves it

Do:

- unify the build truth
- remove guessed artifact paths from critical flows
- strengthen the controller proof boundary
- clearly separate canonical flows from dev-only overrides
- reduce reachable crash-style runtime failures
- make docs, scripts, workflows, and tests tell the same story

## Definition of done

The work is done when:

- `verify-build.sh`, `build-controller-app.sh`, and `build-release.sh` share one toolchain/bootstrap model
- `build-release.sh` no longer depends on guessed `.build/$CONFIG/oracle`
- `verify-build.sh` no longer uses guessed `.build/release/oracle` for canonical smoke
- controller-side behavioral proof is materially stronger
- canonical docs no longer rely on raw `.build/...` paths
- reachable crash-style runtime failures have been audited and reduced
- docs, scripts, workflows, and tests now describe the same bounded product
