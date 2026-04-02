# OracleOS Product Contract v2

> **This file is the authoritative source of truth for what Oracle OS is, does, and guarantees.**  
> Milestone docs at the repo root are historical artifacts; this file supersedes them.

---

## What Oracle OS Is

Oracle OS is a **Swift-native macOS automation runtime** that gives AI agents reliable,
approval-gated control over macOS applications through three surfaces:

1. **MCP** — Model Context Protocol tool server (30 tools)
2. **Controller** — Native macOS GUI for human-in-the-loop monitoring and approval
3. **CLI** — `oracle` binary for scripted access and recipe execution

Oracle OS is **not** a web service, a cloud product, or a general-purpose agent framework.  
It is intentionally scoped to macOS desktop automation with a strong sandbox boundary.

---

## Core Guarantees

### 1. All advertised MCP tools are implemented

Every tool name declared in `MCPTools.swift` must have a corresponding handler in `MCPDispatch.swift`.  
The guard script `scripts/mcp_boundary_guard.py` and `Tests/OracleOSTests/MCP/MCPToolCoverageTests.swift`  
enforce this contract on every CI run.

**30 tools in 9 categories:**

| Category | Tools |
|----------|-------|
| Perception | `oracle_context`, `oracle_state`, `oracle_find`, `oracle_read`, `oracle_inspect`, `oracle_element_at`, `oracle_screenshot` |
| Actions | `oracle_click`, `oracle_type`, `oracle_press`, `oracle_hotkey`, `oracle_scroll`, `oracle_focus`, `oracle_window` |
| Wait | `oracle_wait` |
| Vision | `oracle_parse_screen`, `oracle_ground` |
| Memory | `oracle_memory_query`, `oracle_memory_draft` |
| Experiments | `oracle_experiment_search` |
| Architecture | `oracle_architecture_review`, `oracle_candidate_review` |
| Recipes | `oracle_recipes`, `oracle_run`, `oracle_recipe_show`, `oracle_recipe_save`, `oracle_recipe_delete` |
| Workflows | `oracle_workflow_mine`, `oracle_workflow_list`, `oracle_workflow_execute` |

### 2. Approval-gated actions

Risky actions (click, type, press, hotkey, scroll, focus, window, recipe steps marked `requires_approval`)
pass through `PolicyEngine` and may be gated on user approval via `ApprovalStore`.  
An `approval_request_id` token is returned for gated actions and must be supplied to resume them.

### 3. Runtime spine is stable and not broken by surface changes

The runtime bootstrap sequence must never be altered without an ADR:

```
RuntimeBootstrap → BootstrappedRuntime → RuntimeContainer → RuntimeOrchestrator
    → VerifiedExecutor → CommandRouter → WorkspaceRunner / Automation
```

Surface code (MCP, Controller, CLI) is a consumer of this spine, never a mutator.

### 4. Side-effect taxonomy

Three tiers of write operations are recognized:

| Tier | Scope | Examples |
|------|-------|---------|
| **Gated** | User-approved desktop actions | click, type, hotkey via VerifiedExecutor |
| **Service** | Infrastructure persistence | telemetry, traces, memory, graph, recipes, workflows |
| **Read-only** | Perception only | AXScanner, VisionScanner (captures only) |

`VerifiedExecutor` governs Tier 1 writes only. Tier 2 writes happen in their respective service layers.

### 5. Build must be clean

`swift build` must produce zero errors and zero warnings.  
The CI workflow `ci.yml` enforces this on every push to `main`.

---

## What Oracle OS Does Not Guarantee

- Vision grounding accuracy (VLM-dependent, best-effort)
- Experiment search determinism (parallel worktree isolation, OS-scheduler-dependent)
- Workflow synthesis coverage (pattern mining requires sufficient trace history)
- Sub-second tool latency (macOS AX accessibility can be slow)

---

## Architecture Reference

See [docs/architecture/runtime_spine.md](architecture/runtime_spine.md) for the runtime spine ADR.  
See [docs/BASELINE_REPAIR_PASS.md](BASELINE_REPAIR_PASS.md) for the current repair pass state.  
See [ProjectMemory/README.md](../ProjectMemory/README.md) for project memory conventions.  
See [CONTRIBUTING.md](../CONTRIBUTING.md) for contribution guidelines.

---

## Version

OracleOS v2.0.x — contract established 2025-08 repair pass.
