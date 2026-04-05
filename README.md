<div align="center">

# OracleOS

**A local macOS agent runtime written in Swift.**

Every effect on your machine flows through one auditable, policy-enforced execution spine before it is committed.

[![CI](https://github.com/dawsonblock/ORC1/actions/workflows/ci.yml/badge.svg)](https://github.com/dawsonblock/ORC1/actions/workflows/ci.yml)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://swift.org)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://developer.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## Overview

OracleOS is a **local macOS agent runtime** whose three supported surfaces are:

| Surface | Entry point | Role |
| --- | --- | --- |
| **OracleController** | native macOS app | human operator UI |
| **MCP server** | `MCPDispatch` | 30 typed `oracle_*` tools for AI agents |
| **CLI** | `oracle` binary | setup, doctor, status tooling |

Historical rebuild, phase, and deployment documents live in [docs/archive](docs/archive) — archaeology only, not the current contract.

---

## Quick Start

**Requirements:** macOS 14+, Swift 6, Xcode command-line tools, Accessibility and Screen Recording permissions for UI automation.

```bash
git clone https://github.com/dawsonblock/ORC1.git
cd ORC1
swift build
swift test
bash scripts/verify-build.sh   # canonical local proof
```

<details>
<summary>Controller app (native UI)</summary>

```bash
# Run from source
swift run OracleController

# Open in Xcode
open OracleController.xcworkspace

# Unsigned local build
./scripts/build-controller-app.sh --configuration debug --skip-sign
```

The controller's readiness contract: Accessibility and Screen Recording permissions granted, host bridge reachable, and local Application Support storage writable. Vision sidecar and Claude-backed copilot support are optional extensions, not blockers for the manual operator surface.

</details>

<details>
<summary>CLI commands</summary>

```bash
./.build/debug/oracle setup
./.build/debug/oracle doctor
./.build/debug/oracle status
```

</details>

---

## Execution Spine

Every main-path effect flows through a single auditable chain before being committed to state:

```
RuntimeBootstrap
  └─▶ RuntimeOrchestrator.submitIntent(_:)
        └─▶ MainPlanner.plan(intent:context:)
              └─▶ VerifiedExecutor.execute(_:)
                    └─▶ CommandRouter
                          ├─▶ UIRouter
                          └─▶ CodeRouter
                                └─▶ CommitCoordinator.commit(_:)
```

**Known deliberate exceptions — documented and bounded:**

- **`oracle_experiment_search`** — bypasses `RuntimeOrchestrator` and `VerifiedExecutor` by design. Isolation is provided by git worktree sandboxing. All result payloads carry `execution_context = sandbox` and `committed_to_workspace = false`.
- **`Doctor.swift` / `SetupWizard.swift`** — tooling-only shell entry points.
- **`vision-sidecar/`** — optional service boundary; not a committed-state authority.

On the MCP surface, `MCPDispatch` is the single public entry point and `MCPRuntimeHost` is the only component that owns runtime bootstrap and reuse.

---

## MCP Surface

OracleOS exposes **30 stable public tools** across 9 categories via the Model Context Protocol.

| Category | Tools |
| --- | ---: |
| Perception | 7 |
| Actions | 7 |
| Recipes | 5 |
| Workflows | 3 |
| Architecture | 2 |
| Vision | 2 |
| Memory | 2 |
| Wait | 1 |
| Experiments | 1 |
| **Total** | **30** |

Full tool list, signatures, and inputs: [ORACLE-MCP.md](ORACLE-MCP.md).

---

## Repository Layout

```
Sources/
  OracleOS/               runtime, planning, MCP, memory, execution core
  OracleController/       native controller UI
  OracleControllerHost/   controller host process and runtime bridge
  OracleControllerShared/ typed action/control, diagnostics, and trace contracts
  oracle/                 CLI entry points
Tests/                    unit, governance, and eval suites
docs/                     live documentation and archived history
ProjectMemory/            ADRs, risk register, roadmap, known-good patterns
recipes/                  replayable JSON workflows
scripts/                  build, packaging, guard, and verification helpers
vision-sidecar/           optional Python vision service
web/                      disconnected demo scaffold (not part of the runtime contract)
```

`OracleControllerShared` is split by contract boundary: `ControllerModels.swift` (action/control/session), `ControllerDiagnosticsModels.swift` (diagnostics and host state), and `ControllerTraceModels.swift` (trace, recipe, and dashboard payloads).

---

## Development

```bash
swift build
swift test
bash scripts/verify-build.sh          # canonical proof — runs all guards + full test suite
```

Individual guards:

```bash
python3 scripts/mcp_boundary_guard.py
python3 scripts/architecture_guard.py
python3 scripts/execution_boundary_guard.py
```

`bash scripts/verify-build.sh` is the canonical local proof path. It runs the three guard scripts, a release build, the full Swift test suite, and writes evidence to `local/verify/latest/`. The CI workflow (`.github/workflows/ci.yml`) runs the same path and publishes that directory as the shared proof artifact.

---

## Scope Boundaries

This README does not claim:

- **Build certification** — canonical proof is `bash scripts/verify-build.sh` (local) and the CI artifact (shared).
- **Zero warnings** — see [STATUS.md](STATUS.md) and [BASELINE.md](BASELINE.md) for the current evidence posture.
- **Universal executor coverage** — `oracle_experiment_search` is a deliberate exception; the desktop Wait action is a host-side observational check, not an executor path.

---

## Live Reference Docs

| Document | Purpose |
| --- | --- |
| [STATUS.md](STATUS.md) | Current repo state and known limits |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Runtime model and execution spine |
| [ORACLE-MCP.md](ORACLE-MCP.md) | Public MCP tool catalog |
| [docs/PRODUCT_CONTRACT.md](docs/PRODUCT_CONTRACT.md) | Live product surface and guarantees |
| [AUDIT.md](AUDIT.md) | Truth audit and cleanup findings |
| [BASELINE.md](BASELINE.md) | Point-in-time baseline and evidence notes |
| [docs/REPO_FACTS.md](docs/REPO_FACTS.md) | Generated package, tree, and MCP inventory |
| [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) | Release gate checklist |
| [docs/archive](docs/archive) | Archived rebuild, milestone, and handoff history |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/GOVERNANCE.md](docs/GOVERNANCE.md) for contributor expectations and the normative governance contract.

## License

[MIT](LICENSE)
