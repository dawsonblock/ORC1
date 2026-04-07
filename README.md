# OracleOS

**A macOS 14+ local automation runtime written in Swift.**

Supported runtime surfaces in this checkout: the OracleController app, the MCP server, and the `oracle` CLI.

[![CI](https://github.com/dawsonblock/ORC1/actions/workflows/ci.yml/badge.svg)](https://github.com/dawsonblock/ORC1/actions/workflows/ci.yml)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://swift.org)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://developer.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Overview

OracleOS is a **macOS-local automation runtime**. Execution stays local on macOS. If configured, the reasoning layer may call local or remote OpenAI-compatible backends. It is not a cross-platform runtime, cloud service, or general-purpose autonomous software engineering platform.

The three supported runtime surfaces are:

| Surface | Entry point | Role |
| --- | --- | --- |
| **OracleController** | native macOS app | human operator UI |
| **MCP server** | `MCPDispatch` | 30 typed `oracle_*` tools for AI agents |
| **CLI** | `oracle` binary | setup, diagnostics, dashboard snapshot, status, version, and help tooling |

Historical rebuild, phase, and deployment documents live in [docs/archive](docs/archive) — archaeology only, not the current contract.

---

## Supported Platform

The supported Swift runtime build and test path is **macOS 14+ only**.

The runtime depends on Apple accessibility frameworks and the vendored AX layer in `Vendor/AXorcist`, so `swift build`, `swift test`, and the supported controller or MCP runtime flow require macOS. Linux may run some repository-analysis or guard scripts, but it is not a supported platform for the Swift runtime build.

`bash scripts/verify-build.sh` is the canonical local proof path for that supported runtime. It is fail-fast, writes evidence only under `local/verify/latest/`, and should be treated as the release-gate verifier in this checkout.

---

## Execution Model

The supported main-path execution spine is:

`RuntimeBootstrap -> RuntimeOrchestrator -> MainPlanner -> VerifiedExecutor -> CommandRouter -> UIRouter / CodeRouter -> CommitCoordinator`

On the live runtime path, `RuntimeOrchestrator` plans from committed state and, when a workspace root is available from intent metadata or committed state, builds an explicit `PlannerContext` with a workspace-scoped repository snapshot plus a bounded set of advisory project-memory candidates. Edit-capable code actions still fail closed when no workspace root can be resolved.

---

## Documented Exceptions

These are bounded exceptions and are **not** part of the guaranteed main-path execution contract:

- `oracle_experiment_search`
- `oracle doctor` and `oracle setup`
- optional experimental read-only perception via `vision-sidecar/`

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

### Controller App

```bash
# Run from source
swift run OracleController

# Open in Xcode
open OracleController.xcworkspace

# Unsigned local build
./scripts/build-controller-app.sh --configuration debug --skip-sign
```

The controller's readiness contract: Accessibility and Screen Recording permissions granted, host bridge reachable, and local Application Support storage writable. The optional vision sidecar is outside the core authority chain and is not required for the supported manual operator surface.

### CLI Commands

```bash
./.build/debug/oracle setup
./.build/debug/oracle doctor
./.build/debug/oracle dashboard
./.build/debug/oracle status
./.build/debug/oracle version
./.build/debug/oracle help
```

`oracle mcp` launches the MCP surface. `oracle dashboard` prints a non-interactive terminal dashboard snapshot.

On the MCP surface, `MCPDispatch` is the single public entry point and `MCPRuntimeHost` is the reusable runtime owner behind it.
`MCPRuntimeHost` still performs eager workspace binding for compatibility with the memory tools, but live planning now resolves workspace context inside `RuntimeOrchestrator` per intent.

---

## MCP Surface

OracleOS exposes **30 public tools** across 9 categories via the Model Context Protocol.

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

```text
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
python3 scripts/cli_contract_guard.py
python3 scripts/mcp_boundary_guard.py
python3 scripts/architecture_guard.py
python3 scripts/execution_boundary_guard.py
```

`bash scripts/verify-build.sh` is the canonical local proof path. It runs the guard scripts, a release build, non-interactive `oracle` CLI smokes, the full Swift test suite, and writes evidence to `local/verify/latest/`. The CI workflow (`.github/workflows/ci.yml`) runs the same path and publishes that directory as the `canonical-verify-evidence` artifact.
It also records the verification environment in `local/verify/latest/environment.txt`.

---

## Scope Boundaries

This README does not claim:

- **Build certification** — canonical proof is `bash scripts/verify-build.sh` (local) and the CI artifact (shared).
- **Zero warnings** — see [STATUS.md](STATUS.md) and [BASELINE.md](BASELINE.md) for the current evidence posture.
- **Fully local reasoning** — execution stays local, but reasoning may use configured local or remote OpenAI-compatible backends.
- **Universal executor coverage** — `oracle_experiment_search` is a deliberate exception; the desktop Wait action is a host-side observational check, not an executor path.

---

## Live Reference Docs

| Document | Purpose |
| --- | --- |
| [STATUS.md](STATUS.md) | Current repo state and known limits |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Runtime model and execution spine |
| [ORACLE-MCP.md](ORACLE-MCP.md) | Public MCP tool catalog |
| [docs/PRODUCT_CONTRACT.md](docs/PRODUCT_CONTRACT.md) | Live product surface and guarantees |
| [docs/OPERATOR_CHEAT_SHEET.md](docs/OPERATOR_CHEAT_SHEET.md) | Practical "what can I ask it to do?" guide |
| [docs/MCP_TOOL_EXAMPLES.md](docs/MCP_TOOL_EXAMPLES.md) | Tool-by-tool walkthrough of all 30 MCP capabilities |
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
