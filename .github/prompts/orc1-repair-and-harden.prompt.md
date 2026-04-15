---
description: "First pass for ORC1: repair and harden the repo without changing architectural intent. Use for toolchain and bootstrap unification, artifact-path cleanup, runtime behavioral proof, CI cleanup, supported-surface boundary tightening, failure hardening, and docs-to-code alignment."
name: "Run ORC1 Repair and Harden"
argument-hint: "Optional subsystem, script path, runtime edge, or product boundary to emphasize in the repair-and-harden pass."
agent: "ORC1 Repo Hardening"
---

Use the ORC1 Repo Hardening agent for the first pass in this repository.

Repair and harden the repo without changing architectural intent.

Rules:

- no greenfield rewrite
- no re-platforming
- no speculative features
- no scope expansion
- do not claim production-ready unless code, scripts, tests, and CI prove it

Read the repo first. Trust code, manifests, scripts, workflows, runtime paths, and tests over comments. If docs disagree with code, fix one so they match.

What to fix:

- unify build, verify, and release scripts behind one toolchain and bootstrap path
- remove brittle SwiftPM artifact path assumptions
- add behavioral proof for real runtime and operator boundaries
- separate supported core from optional, demo, or experimental surfaces
- clean CI so canonical proof paths are obvious
- replace reachable crash-style guardrails with explicit failures where appropriate

Do this in order:

1. Inspect reality

Read:

- Package.swift
- README and build or release docs
- scripts/verify-build.sh
- scripts/build-controller-app.sh
- scripts/build-release.sh
- .github/workflows/\*
- Sources/\*
- Tests/\*

Determine:

- canonical build path
- canonical verification path
- canonical release path
- which scripts disagree on toolchain selection
- which scripts assume wrong artifact paths
- which product surfaces are truly supported
- where runtime boundary proof is missing

2. Unify toolchain and bootstrap

Create one shared build bootstrap path and reuse it in:

- scripts/verify-build.sh
- scripts/build-controller-app.sh
- scripts/build-release.sh

Requirements:

- consistent DEVELOPER_DIR
- consistent Swift invocation strategy
- deterministic failure if the Apple toolchain is unavailable
- no duplicated drift-prone logic

3. Remove brittle artifact assumptions

Replace hardcoded `.build/...` release path assumptions with authoritative path discovery such as `swift build --show-bin-path`.
Audit other scripts for the same problem.

4. Add real behavioral proof

Add or improve targeted tests for:

- controller to host bridge startup and handshake
- MCP decode to dispatch to typed response
- approval-gated execution or edit path
- packaging or release smoke
- supported boundary failures

Prefer a few real integration tests over many shallow tests.

5. Tighten product boundaries

Classify surfaces as:

- supported core
- optional supported extension
- experimental
- demo or archive only

Make docs, packaging, and runtime messaging match.
Do not describe externally provisioned sidecars as self-contained.

6. Clean CI

Audit workflows and classify each as:

- canonical product proof
- release proof
- architecture guardrail
- supplemental scanner
- stale or noise

Keep the proof workflows.
Trim, relabel, or remove misleading noise.

7. Harden failure handling

Audit runtime-reachable:

- fatalError
- assertionFailure
- preconditionFailure
- force unwraps
- "unreachable" branches

Keep hard traps only for truly impossible states.
Replace reachable ones with explicit typed or runtime failures.

8. Align docs to truth

Update docs so they match:

- real build path
- real verify path
- real release path
- real supported scope
- optional, demo, external surfaces
- what CI actually proves

Deliver:

- code changes in place
- short repair summary
- proof summary
- remaining risk list

Definition of done:

- one consistent toolchain or bootstrap path across build and release scripts
- no critical guessed artifact paths
- behavioral proof at main runtime edges
- explicit supported versus optional or demo boundaries
- CI reflects real proof
- docs match code and packaging
