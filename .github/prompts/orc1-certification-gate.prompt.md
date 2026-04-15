---
description: "Final certification gate for ORC1: determine whether the repaired repo is honestly production-grade for its stated scope, apply only blocker-level fixes, and lower claims when evidence is insufficient."
name: "Run ORC1 Certification Gate"
argument-hint: "Optional supported scope, subsystem, workflow, or blocker area to emphasize in the final certification gate."
agent: "ORC1 Repo Hardening"
---

Use the ORC1 Repo Hardening agent for the final certification pass in this repository.

You are working inside the repaired ORC1 repository.

This is the final certification gate.

Your job is to determine whether the repository can honestly pass as a production-grade build for its stated scope.
Do not assume it passes because earlier repair work was completed.
Re-audit everything from the repaired state and apply only blocker-level fixes required to make the repo truthful, deterministic, and supportable.

This is not a feature pass.
This is not a refactor pass unless refactoring is necessary to remove certification blockers.
This is not a redesign pass.

You may fix blockers.
You may simplify brittle logic.
You may delete misleading or stale paths.
You may tighten claims.
You may improve tests where a missing test is itself a blocker.

You may not broaden scope.
You may not add speculative functionality.
You may not market the repo.
You may not call it production-ready unless the evidence is concrete.

## Certification standard

The repository may only be described as production-grade for its actual supported scope if all of the following are true:

1. Build determinism
   All documented build, verify, and release flows use one consistent toolchain/bootstrap path.
   No critical script depends on guessed artifact locations or environment coincidence.
2. Behavioral proof
   The main supported runtime/operator boundaries are covered by meaningful tests or executable verification steps.
   Passing CI must mean something real.
3. Product boundary honesty
   Supported core, optional extensions, experimental surfaces, and demo/archive-only surfaces are clearly separated in code, docs, and packaging.
   Nothing optional is presented as core.
   Nothing externally dependent is described as self-contained if it is not.
4. Failure clarity
   Runtime-reachable invalid states fail explicitly and predictably.
   Crash-style traps are limited to truly impossible states by construction.
5. CI truthfulness
   The workflows shown as the repo's proof actually correspond to the supported product paths.
   Generic scanners or template workflows do not masquerade as runtime certification.
6. Documentation truth
   README, build docs, release docs, and packaging behavior all describe the same reality.
   Claims do not exceed evidence.

## Operating mode

You are acting like a hostile certifier.

That means:

- assume drift is still present until proven otherwise
- assume earlier fixes may be incomplete
- assume tests may be shallow until they prove otherwise
- assume docs may still overclaim
- assume workflow names may exaggerate what they actually verify

Do not be impressed by architecture.
Do not be impressed by number of tests.
Do not be impressed by clean code alone.

Only certify what is actually proven.

## Required audit procedure

### Phase 1 - establish the canonical truth

Read and confirm the real supported product shape from:

- Package.swift
- README
- scripts/\*
- .github/workflows/\*
- Sources/\*
- Tests/\*

Write down internally:

- the single canonical build path
- the single canonical verification path
- the single canonical release path
- the supported product surfaces
- the optional/external/demo/experimental surfaces

If the repo does not clearly have a single truth for each of these, that is a blocker.

### Phase 2 - certify build determinism

Audit every build-related script and every workflow that builds or packages.

Requirements:

- one shared toolchain/bootstrap source of truth
- consistent DEVELOPER_DIR handling
- consistent swift invocation strategy
- authoritative artifact discovery
- no silent fallback that changes behavior across machines

Perform blocker fixes only where needed.

If two scripts build the same product differently, resolve that before anything else.

### Phase 3 - certify behavioral proof

Identify the supported runtime boundaries that matter most.
Examples may include:

- controller start and bridge handshake
- MCP request decode and typed dispatch
- approval-gated execution path
- release/package smoke
- operator-facing failure handling

For each claimed supported boundary, determine:

- is there a meaningful test or executable proof path?
- does it assert behavior rather than shape?
- will it fail if wiring breaks?

If not, add the minimum necessary proof or reduce the support claim.

Do not add broad test suites for appearance.
Add only what certification requires.

### Phase 4 - certify boundary honesty

Audit:

- optional sidecars
- Python-dependent paths
- demo web UI or archived surfaces
- experimental tools
- anything bundled but not actually self-contained

Fix any mismatch among:

- docs
- packaging
- runtime messaging
- CI assumptions

If a component is shipped but not supportable, either classify it correctly or remove it from the certified story.

### Phase 5 - certify failure handling

Search for runtime traps and brittle assumptions:

- fatalError
- assertionFailure
- preconditionFailure
- force unwraps
- "unreachable" defaults
- hidden fallback behavior

For each one:

- prove it is structurally impossible, or
- convert it into explicit typed/runtime failure if reachable from real input, version drift, or operator action

This is a certification blocker area.
A production claim cannot rest on hidden crash edges at ordinary boundaries.

### Phase 6 - certify CI truth

Classify every workflow:

- canonical build/verify proof
- canonical release proof
- architecture guardrail
- supplemental security/scanner
- stale/noise

Then enforce clarity:

- canonical workflows must correspond to actual documented usage
- supplemental workflows must not imply product certification
- stale/noise workflows should be removed or clearly sidelined

If badges, docs, or workflow names overstate reality, fix them.

### Phase 7 - certify docs against evidence

Re-read all operator-facing documentation after code and workflow audit.

Make docs match evidence exactly.

If something is only verified on one platform, say so.
If a sidecar is optional and externally provisioned, say so.
If release packaging is supported only through one script path, document that one path.
If the repo is not fully production-grade, say what it is production-grade for and what remains uncertified.

## Required outputs

Apply only blocker-level repo changes.

Then produce these outputs:

1. Certification verdict
   One of:
   - Certified for production use within stated scope
   - Not certified
2. Scope statement
   If certified, state the exact supported scope and platform assumptions.
   If not certified, state the maximum honest claim.
3. Blocker report
   List every blocker found during the certification pass.
   For each blocker:
   - what it was
   - whether it was fixed
   - why it mattered
4. Evidence summary
   Reference the scripts, workflows, tests, and docs that justify the verdict.
5. Residual risk statement
   List remaining risks that do not block the narrower certified scope, or explain why they still block certification.

## Decision rule

If there is doubt, do not certify.
Lower the claim instead.

Do not optimize for passing.
Optimize for truth.

## Definition of done

The work is done when one of these is true:

A. The repo is honestly certifiable for a clearly bounded production scope, with supporting evidence in code, tests, scripts, workflows, and docs.

or

B. The repo is not certifiable, and the final output clearly states the narrowest truthful claim and the exact remaining blockers.

Anything in between is failure.
