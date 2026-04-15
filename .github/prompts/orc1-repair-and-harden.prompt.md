---
description: "Targeted ORC1 repair pass for unresolved hardening gaps only: unify build and release bootstrap logic, remove remaining .build artifact assumptions, strengthen controller-side proof, audit reachable crash-style failures, and align docs and CI to the repaired truth."
name: "Run ORC1 Repair and Harden"
argument-hint: "Optional unresolved area to emphasize: bootstrap drift, release artifact discovery, controller proof, path drift, or crash-style guardrails."
agent: "ORC1 Repo Hardening"
---

Use the ORC1 Repo Hardening agent for the next repair pass in this repository.

You are working inside the latest extracted ORC1 repository.

Do not do a broad rewrite.
Do not expand scope.
Do not add speculative features.
Do not touch working architecture just to make it look cleaner.

This pass is for closing the remaining hardening gaps that are still present in the current upload.

Read the repository first.
Trust code, scripts, manifests, workflows, tests, and runtime paths over comments.
If docs disagree with code, fix one so they match.
Do not leave contradictions in place.

## What is already good

Do not disturb these unless a blocker forces it:

- the overall architectural shape is coherent
- the product boundary is mostly honest
- `web/` is already demoted from the supported core
- `vision-sidecar/` is already treated as optional or experimental
- the repo already has meaningful runtime proof in parts of `OracleOSTests`
- top-level docs are substantially more aligned than earlier versions

This pass is not about redoing that work.
It is about closing the specific remaining gaps.

## Primary unresolved issues

1. `scripts/build-release.sh` still hardcodes SwiftPM artifact layout using `.build/$CONFIG/oracle`
   This must be removed.
   The release script must use authoritative artifact discovery such as `swift build --show-bin-path` or an equally reliable resolved-path approach.
2. Build and release scripts still do not share one toolchain or bootstrap path
   `scripts/verify-build.sh` has stricter Xcode or Swift toolchain handling than:
   - `scripts/build-controller-app.sh`
   - `scripts/build-release.sh`
     That inconsistency must be eliminated.
     Packaging and release must not silently use a different toolchain path than verification.
3. Controller-side behavioral proof is still too thin compared with core runtime proof
   There are controller tests, but the repo still lacks enough high-value behavioral proof around real controller, host, and runtime boundaries.
4. Some `.build/...` assumptions still survive in docs and dev fallback code
   These need to be either:
   - removed
   - marked clearly as development-only
   - or replaced with stronger discovery logic where possible
5. Crash-style guardrails still exist and need final audit
   Audit reachable uses of:
   - `fatalError`
   - `assertionFailure`
   - `preconditionFailure`
   - force unwraps
   - `"unreachable"` branches
     Keep only those that are truly impossible by construction.
     Replace reachable ones with explicit typed or runtime failure.

## Mission

Make the repository internally consistent enough that its documented build, verify, and release story matches the actual code and scripts.

Do this in order.

### Phase 1 - unify toolchain and bootstrap

Inspect:

- `scripts/verify-build.sh`
- `scripts/build-controller-app.sh`
- `scripts/build-release.sh`

Required outcome:
Create one shared shell helper or one shared bootstrap section used by all build-related scripts.

Requirements:

- consistent `DEVELOPER_DIR` handling
- consistent use of `xcrun swift` or another single deliberate strategy
- same toolchain assumptions for verify, controller build, and release build
- deterministic failure with clear error messages if the required Apple toolchain is unavailable
- no duplicated drift-prone bootstrap logic

Do not leave one script special.
The canonical verifier and canonical packagers must build with the same toolchain logic.

### Phase 2 - remove brittle release artifact assumptions

Fix `scripts/build-release.sh`.

Requirements:

- stop assuming `.build/$CONFIG/oracle`
- resolve the actual binary output path from SwiftPM
- keep configuration handling correct
- keep archive or bundle output layout intact if it is otherwise correct

Then audit the rest of the repo for critical-path assumptions like:

- `.build/debug/...`
- `.build/release/...`
- architecture-specific `.build/...` guesses

Where these are part of product or release behavior, replace them.
Where they are only development-convenience fallbacks, label them clearly and keep them behind lower-precedence lookup.

### Phase 3 - strengthen controller-side proof

Focus on high-value behavioral proof, not broad shallow test growth.

Add or improve tests for the real controller boundary, especially:

- controller startup and host process launch path
- helper or host resolution precedence
- handshake or readiness behavior between controller and host
- failure handling when the host binary is missing, invalid, or unreachable
- packaged controller smoke behavior if there is a realistic way to assert it
- any real user-visible edge where breakage would not currently be caught

Guidelines:

- prefer a few real integration-style tests over many object-construction tests
- assert behavior and failure modes
- ensure tests would fail if wiring drifts

Do not pad the suite with cosmetic tests.

### Phase 4 - clean remaining path drift in docs and fallback code

Audit:

- `README.md`
- controller docs
- release docs
- status or release summaries
- controller host discovery code
- any launch scripts or examples

Required outcome:

- documented canonical product paths must not depend on raw `.build/...` assumptions
- if `.build/...` examples remain for development overrides, label them as development-only
- packaged or supported flows must point to the canonical scripts or bundled artifacts
- host discovery should prefer bundled or canonical paths first, then explicitly marked dev overrides only after that

Do not erase useful development workflows.
Just stop presenting them as the main supported path.

### Phase 5 - final runtime guardrail audit

Audit runtime-critical code for crash-style failure paths.

For each occurrence:

- determine whether it is truly impossible by construction
- if yes, keep it only if the invariant is well justified
- if no, replace it with explicit typed failure, guarded rejection, or a controlled operator-facing error

Pay special attention to:

- `Sources/OracleOS/Runtime/RuntimeContext.swift`
- `Sources/OracleOS/TaskLedger/TaskLedger.swift`
- `Sources/OracleOS/MCP/MCPTools.swift`

Do not weaken invariants.
Convert hidden fragility into explicit behavior.

### Phase 6 - align CI and docs to the repaired truth

After code and test changes, re-check:

- `README.md`
- `docs/PRODUCT_CONTRACT.md`
- `STATUS.md`
- `docs/RELEASE_READY_SUMMARY.md`
- `.github/workflows/ci.yml`
- `.github/workflows/controller-release.yml`
- `.github/workflows/architecture.yml`

Make sure these state the same reality:

- canonical build path
- canonical verify path
- canonical release path
- supported surfaces
- optional or experimental surfaces
- what CI proves
- what still depends on platform assumptions

Do not increase claims beyond evidence.

## Deliverables

Make the changes directly in the repo.

Then produce:

1. Repair summary
   State exactly:
   - what remained broken in this upload
   - what you changed
   - what you intentionally left unchanged
2. Proof summary
   State:
   - which scripts now share the common bootstrap or toolchain logic
   - how release artifact discovery now works
   - which controller-side behavioral tests were added or strengthened
   - which docs were corrected
3. Remaining risk list
   State any remaining narrow risks, especially:
   - macOS-only assumptions
   - optional sidecar dependencies
   - dev-only fallback paths that still exist by design
   - anything still not proven by tests

## Constraints

Do not:

- rewrite architecture
- add new product surfaces
- remove useful dev overrides unless they are actively misleading
- paper over runtime failures
- claim full production certification unless the repo really proves it

Do:

- fix the remaining script drift
- make release packaging authoritative
- strengthen the controller proof boundary
- make docs and code say the same thing
- leave the repo stricter and more honest than it is now

## Definition of done

The work is done when:

- `verify-build.sh`, `build-controller-app.sh`, and `build-release.sh` share one toolchain or bootstrap model
- `build-release.sh` no longer depends on guessed `.build/$CONFIG/oracle`
- controller-side behavioral proof is materially stronger
- `.build/...` assumptions are no longer part of the canonical supported path
- runtime-reachable crash-style failures have been audited and reduced
- docs, scripts, and CI describe the same bounded product
