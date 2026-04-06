# Persistence Namespace

## Purpose

The `Persistence/` directory is the **designated home for all Tier-3 (destructive / persistent) write operations** inside OracleOS.

Tier-3 writes include:

- File system mutations (`FileManager.write*`, `Data.write(to:)`, file creation/deletion)
- Shell escapes that produce file output
- Database or structured-store upserts
- Recipe saves / deletes

## Where persistence-designated code lives today

Currently OracleOS scatters persistence across several stores.  This README marks the canonical landing zone:

| Store | Current location | Tier |
| --- | --- | --- |
| `UnifiedMemoryStore` | `Sources/OracleOS/Memory/` | Tier 3 — writes memory + project records |
| `ProjectMemoryStore` | `Sources/OracleOS/Memory/` | Tier 3 — writes markdown to disk |
| `RecipeStore` | `Sources/OracleOS/MCP/` | Tier 3 — saves recipe JSON to disk |
| `WorkflowIndex` | `Sources/OracleOS/Planning/` | Tier 3 — writes workflow plan index |
| `ExperienceStore` | `Sources/OracleOS/Learning/` | Tier 3 — persists event history |
| `RepositoryIndexer` | `Sources/OracleOS/Code/` | Tier 3 — writes code-intelligence index |
| `WorkspaceRunner` | `Sources/OracleOS/Code/` | Tier 3 — writes temp workspace files |
| `DiagnosticsWriter` / `MetricsRecorder` / `StrategyDiagnostics` | `Sources/OracleOS/Common/` | Tier 3 — writes diagnostics / metrics |
| `ApprovalStore` | `Sources/OracleOS/Intent/` | Tier 3 — persists approval records |
| `FileEventStore` / `CommitWAL` | `Sources/OracleOS/Events/` | Tier 3 — persists event log / WAL |

## Rules

1. **New persistent stores** must be placed in `Sources/OracleOS/Persistence/` (or a subdirectory).
2. **Existing stores** should migrate here incrementally — do not move them until you also update all import paths and run `swift build`.
3. **The `execution_boundary_guard.py`** script scans for file-write patterns outside this namespace and the stores listed above; any new writer not listed here will be flagged.
4. **Read-only** operations (loading, querying) do not need to live here, but co-locating them with their write counterparts is encouraged.

## enforcement_boundary_guard.py integration

`scripts/execution_boundary_guard.py` is configured to allow `FileManager` and `Data.write` patterns only inside:

- `Sources/OracleOS/Memory/`
- `Sources/OracleOS/Persistence/`
- `Sources/OracleOS/MCP/` (RecipeStore only)
- `Sources/OracleOS/Planning/` (WorkflowIndex only)
- `Sources/OracleOS/Learning/` (ExperienceStore only)

All other locations that contain file-write patterns will cause the guard to exit non-zero.
