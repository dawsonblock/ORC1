---
description: "Second pass for ORC1: hostile verification of build and release truth, proof quality, supported-surface honesty, CI truth, runtime failure handling, and docs-to-code consistency. Use to verify the repair is real and close remaining honesty or drift gaps without broad rework."
name: "Run ORC1 Hostile Verification"
argument-hint: "Optional subsystem, workflow, runtime edge, or honesty gap to emphasize in the hostile verification pass."
agent: "ORC1 Repo Hardening"
---

Use the ORC1 Repo Hardening agent for the second pass in this repository.

This pass is verification, not broad implementation.

Goal:
verify that the first repair is real, find anything still dishonest or fragile, and close remaining gaps without changing architecture.

Rules:

- proof over intent
- no greenfield rewrite
- no scope expansion
- no speculative features
- prefer deletion over duplication
- if docs, CI, code, and packaging disagree, resolve the contradiction

Audit these areas:

1. Build and release truth

Check:

- scripts/verify-build.sh
- scripts/build-controller-app.sh
- scripts/build-release.sh
- any shared helper added
- Package.swift
- workflows invoking these scripts

Verify:

- one toolchain or bootstrap path
- consistent DEVELOPER_DIR
- consistent Swift invocation
- authoritative artifact discovery
- working packaging path

Fix any remaining script drift or duplicate bootstrap logic.

2. Proof quality

Audit tests and reject cosmetic proof.
Verify real behavioral coverage for:

- controller startup or host bridge handshake
- MCP decode and typed dispatch
- approval-gated execution or edit path
- package or release smoke
- runtime edge failures

Strengthen weak tests if they do not fail on broken wiring.

3. Supported surface honesty

Audit:

- README
- build and release docs
- packaging scripts
- runtime messages
- sidecars
- demo, archive, or web surfaces

Verify:

- supported core is explicit
- optional supported extensions are explicit
- experimental, demo, or archive surfaces are clearly not core
- externally provisioned pieces are described honestly

Fix any overclaim.

4. CI truth

Audit all workflows.
Classify each as:

- canonical product proof
- release proof
- architecture guardrail
- supplemental scanner
- stale or noise

Remove, disable, or relabel stale or misleading workflows.
Make sure canonical workflows match documented usage.

5. Runtime failure audit

Search for:

- fatalError
- assertionFailure
- preconditionFailure
- force unwraps
- unreachable defaults

For each:

- prove impossible by construction, or
- convert to explicit typed or runtime failure if reachable

6. Docs-to-code consistency

Re-read docs after the code audit.
Make docs state exactly:

- prerequisites
- supported platforms
- canonical build, verify, and release commands
- what CI proves
- optional, external, and experimental status

Deliver:

- any remaining fixes in place
- verification report
- remaining honesty gaps
- canonical truth summary
- evidence list

Done means:

- hostile re-audit passes
- no critical script still depends on drift-prone assumptions
- behavioral tests prove runtime edges
- CI reflects real proof
- docs, code, packaging, and workflows describe the same product
