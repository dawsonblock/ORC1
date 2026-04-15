---
description: "Final pass for ORC1: hostile certification gate focused on build determinism, behavioral proof, product boundary honesty, failure clarity, CI truthfulness, documentation truth, and whether the repo is honestly certifiable for production use within a stated scope."
name: "Run ORC1 Certification Gate"
argument-hint: "Optional subsystem, supported scope, workflow, or blocker area to emphasize in the certification gate."
agent: "ORC1 Repo Hardening"
---

Use the ORC1 Repo Hardening agent for the final certification pass in this repository.

Act like a hostile certifier.

Do not assume the repo passes because earlier repairs were completed.
Apply only blocker-level fixes needed to make the repo truthful, deterministic, and supportable.

Rules:

- no feature pass
- no redesign
- no scope expansion
- no speculative work
- if there is doubt, do not certify
- lower the claim instead

Certification criteria:

1. build determinism
2. behavioral proof
3. product boundary honesty
4. failure clarity
5. CI truthfulness
6. documentation truth

Procedure:

1. Establish canonical truth

Read:

- Package.swift
- README
- scripts/\*
- .github/workflows/\*
- Sources/\*
- Tests/\*

Determine:

- single canonical build path
- single canonical verification path
- single canonical release path
- supported product surfaces
- optional, external, demo, and experimental surfaces

If there is not one clear truth for each, that is a blocker.

2. Certify build determinism

Audit all build and release scripts and workflows.
Require:

- one shared bootstrap or toolchain source of truth
- consistent DEVELOPER_DIR
- consistent Swift invocation
- authoritative artifact discovery
- no silent fallbacks

Fix only blocker-level issues.

3. Certify behavioral proof

For each claimed supported runtime boundary, verify meaningful proof exists:

- controller start or bridge handshake
- MCP decode or typed dispatch
- approval-gated execution path
- package or release smoke
- operator-facing failure handling

If proof is missing, either add minimum blocker-level proof or reduce the support claim.

4. Certify boundary honesty

Audit:

- sidecars
- Python-dependent paths
- demo web UI
- archived or experimental surfaces
- bundled but not self-contained pieces

Make docs, packaging, runtime messaging, and CI describe them honestly.

5. Certify failure handling

Search for:

- fatalError
- assertionFailure
- preconditionFailure
- force unwraps
- unreachable defaults
- hidden fallbacks

For each:

- prove structurally impossible, or
- convert to explicit failure if reachable

6. Certify CI truth

Classify every workflow:

- canonical build or verify proof
- canonical release proof
- architecture guardrail
- supplemental scanner
- stale or noise

Make canonical workflows match documented usage.
Remove or sideline misleading workflows.

7. Certify docs against evidence

Re-read all docs after the code and workflow audit.
Make docs match evidence exactly.
If support is narrow, say so.
If a sidecar is optional and externally provisioned, say so.
If the repo is not fully production-grade, state the maximum honest claim.

Required outputs:

1. Certification verdict:

- Certified for production use within stated scope
- Not certified

2. Scope statement
3. Blocker report:

- blocker
- fixed or not
- why it mattered

4. Evidence summary:
   reference exact scripts, tests, workflows, and docs
5. Residual risk statement

Decision rule:
If there is doubt, do not certify.

Done means:

- honestly certifiable for a clearly bounded scope with evidence
- or not certifiable, with exact remaining blockers and the narrowest truthful claim
