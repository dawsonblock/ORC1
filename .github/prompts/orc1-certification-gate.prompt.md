---
description: "Final strict certification gate for the repaired ORC1 upload: decide whether the repo can be honestly certified for production use within a clearly bounded scope, and apply only blocker-level fixes where required."
name: "Run ORC1 Certification Gate"
argument-hint: "Optional certification scope, blocker area, workflow, or runtime boundary to emphasize in the final strict certification gate."
agent: "ORC1 Repo Hardening"
---

Use the ORC1 Repo Hardening agent for the final strict certification gate in this repository.

You are working inside the latest repaired ORC1 repository.

This is the final certification gate.

You are not here to improve the repo.
You are here to decide whether it can be honestly certified for production use within a clearly bounded scope.

You may only make blocker-level fixes required to remove certification blockers.
No feature work.
No architectural changes.
No speculative improvements.

If there is doubt, do not certify.
Lower the claim instead.

## Certification criteria (all must be true)

1. Build determinism
   - One consistent toolchain/bootstrap path across:
   - verify
   - controller build
   - release build
   - No script depends on guessed `.build/...` layout for critical paths
   - No silent toolchain fallback that changes behavior across machines

2. Behavioral proof
   - Supported runtime/operator boundaries are covered by meaningful tests or executable verification
   - Tests assert behavior, not just construction or structure
   - CI failure would catch real wiring breakage

3. Product boundary honesty
   - Supported core is clearly defined
   - Optional/experimental/demo surfaces are clearly separated
   - Externally provisioned components are not described as self-contained
   - Packaging does not imply support beyond what is real

4. Failure clarity
   - Runtime-reachable invalid states fail explicitly and predictably
   - Crash-style traps are limited to truly impossible states
   - No hidden fragile edges at normal operator boundaries

5. CI truthfulness
   - Canonical workflows correspond to real product build/verify/release paths
   - Scanner or template workflows do not masquerade as certification
   - CI success reflects real product integrity

6. Documentation truth
   - README, docs, scripts, and workflows describe the same product
   - Build, verify, and release paths are unambiguous
   - Claims do not exceed evidence

## Operating mode

Assume the repo is still wrong until proven otherwise.

Do not be influenced by:

- number of tests
- apparent structure quality
- prior repair claims
- documentation tone

Only accept what is proven by:

- scripts
- code paths
- tests
- workflows
- packaging behavior

## Audit procedure

### Phase 1 - establish canonical truth

From:

- `Package.swift`
- `README.md`
- `scripts/*`
- `.github/workflows/*`
- `Sources/*`
- `Tests/*`

Determine:

- single canonical build path
- single canonical verification path
- single canonical release path
- supported product surfaces
- optional/experimental/demo surfaces

If there is not exactly one clear answer for each, this is a blocker.

### Phase 2 - certify build determinism

Audit:

- `scripts/verify-build.sh`
- `scripts/build-controller-app.sh`
- `scripts/build-release.sh`
- shared bootstrap/helper logic

Requirements:

- identical toolchain/bootstrap model across scripts
- consistent `DEVELOPER_DIR`
- consistent Swift invocation
- authoritative artifact path discovery
- no `.build/$CONFIG/...` assumptions in release-critical paths

If any divergence remains, it is a blocker.

### Phase 3 - certify behavioral proof

Identify supported runtime boundaries and verify real proof exists for them.

At minimum:

- controller startup and host resolution
- MCP decode and typed dispatch
- approval-gated execution path
- release/package smoke or equivalent
- operator-facing failure handling

For each:

- does a test or executable path prove behavior?
- would it fail if wiring breaks?

If not, either:

- add minimal blocker-level proof, or
- reduce the support claim

### Phase 4 - certify boundary honesty

Audit:

- sidecars
- Python-dependent paths
- demo web UI
- archived/experimental components
- bundled vs external behavior

Verify:

- docs, packaging, runtime, and CI all agree on classification
- supported vs optional is not ambiguous
- no overstatement of self-contained capability

### Phase 5 - certify failure handling

Search for:

- `fatalError`
- `assertionFailure`
- `preconditionFailure`
- force unwraps
- unreachable branches

For each:

- prove impossible by construction, or
- convert to explicit failure if reachable

If reachable crash paths exist at real boundaries, certification fails.

### Phase 6 - certify CI truth

Classify workflows:

- canonical build/verify proof
- canonical release proof
- architecture guardrail
- supplemental scanner
- stale/noise

Verify:

- canonical workflows match documented usage
- scanners do not imply certification
- no misleading workflow naming or badge signaling

### Phase 7 - certify docs against evidence

Re-read all docs after code/workflow audit.

Verify:

- build path matches scripts
- verify path matches CI
- release path matches packaging
- supported scope is accurate
- optional/external components are clearly labeled

Lower claims if necessary.

## Required outputs

1. Certification verdict
   One of:
   - Certified for production use within stated scope
   - Not certified

2. Scope statement
   If certified:
   - exact supported scope
   - platform assumptions
   - boundaries of support

   If not certified:
   - narrowest truthful claim

3. Blocker report
   For each blocker:
   - description
   - fixed or not
   - why it matters for certification

4. Evidence summary
   Reference exact:
   - scripts
   - tests
   - workflows
   - docs

   that justify the verdict

5. Residual risk statement
   List:
   - any remaining risks within the certified scope
   - or why risks still block certification

## Decision rule

If any of the six certification criteria are not fully met, do not certify.

## Definition of done

The work is done when one of the following is true:

A. The repo is honestly certifiable for a clearly bounded production scope, backed by code, scripts, tests, workflows, and docs

or

B. The repo is not certifiable, and the output clearly states:

- the exact blockers
- the narrowest truthful claim
- what remains to reach certification
