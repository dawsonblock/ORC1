# Single-Hard-Path Runtime: Phase 1 Completion Status

## ✅ Phase 1 Completed (90% - Build System Boundary Closed)

### What Was Done

1. **Removed `.shell` from Command Enum**
   - ❌ `case .shell(CommandSpec)` eliminated
   - ✅ Added: `.build(BuildSpec)`, `.test(TestSpec)`, `.git(GitSpec)`, `.file(FileMutationSpec)`
   - File: `Sources/OracleOS/Core/Command/Command.swift`

2. **Created 4 Typed Spec Types** (New Files)
   - `BuildSpec.swift` - Structured build with scheme, configuration, extraArgs
   - `TestSpec.swift` - Structured test with filter, failureOnly flag
   - `GitSpec.swift` - Typed git operations (status, diff, commit, etc.)
   - `FileMutationSpec.swift` - File ops (write, delete, append) with content

3. **Updated PolicyEngine**
   - Removed hardcoded `/usr/bin/env` and `/usr/bin/git` allowlist
   - Removed shell-specific policy logic
   - Now validates by CommandPayload type, not executable path
   - File: `Sources/OracleOS/Intent/Policies/PolicyEngine.swift`

4. **Updated Command Routers**
   - `CodeRouter.swift` - Now handles `.build()`, `.test()`, `.git()`, `.file()` payloads
   - `SystemRouter.swift` - Same payload support
   - Both routers call `workspaceRunner.runBuild()`, `runTest()`, `runGit()`, `applyFile()`
   - No more shell execution string building

5. **Extended WorkspaceRunner** 
   - Added `runBuild(_ spec: BuildSpec) async throws -> ProcessResult`
   - Added `runTest(_ spec: TestSpec) async throws -> ProcessResult`
   - Added `runGit(_ spec: GitSpec) async throws -> ProcessResult`
   - Added `applyFile(_ spec: FileMutationSpec) async throws`
   - File: `Sources/OracleOS/Code/Execution/WorkspaceRunner.swift`

### Result

**No `.shell()` anywhere in the command payload.**

All build, test, git, and file operations are now:
1. **Typed** - Spec objects define valid operations
2. **Validated** - Policy checks payload type, not strings
3. **Routed** - CommandRouter → Router → WorkspaceRunner methods
4. **Isolated** - Process() execution only inside DefaultProcessAdapter

---

## ⚠️ Phase 1 Remaining (10% - CLI Tool Routing)

### Issue: CLI Tools Still Direct Process()

Files that need fixing:
- `Sources/oracle/SetupWizard.swift` - Has direct `Process()` calls
- `Sources/oracle/Doctor.swift` - Has direct `Process()` calls
- `Sources/OracleController/HostProcessClient.swift` - Has direct `Process()` calls
- `Sources/OracleControllerHost/CopilotSupport.swift` - Has direct `Process()` calls

### Fix Strategy

These CLI/UI tools should NOT call Process() directly. Instead:

```swift
// OLD (direct Process):
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
process.arguments = ["build"]
try process.run()

// NEW (through RuntimeOrchestrator):
let intent = Intent(objective: "build the workspace")
let command = Command(
    type: .code,
    payload: .build(BuildSpec(workspaceRoot: ".")),
    metadata: CommandMetadata(intentID: UUID())
)
let outcome = try await executor.execute(command)
```

**Minimal fix:** Route CLI process calls through VerifiedExecutor → CommandRouter.

**Impact:** After this fix, ALL process execution flows through one path:
```
RuntimeOrchestrator.submitIntent()
  ↓
VerifiedExecutor.execute(command)
  ↓
CommandRouter.execute()
  ↓
Typed Router (System/Code)
  ↓
WorkspaceRunner.run<Op>()
  ↓
DefaultProcessAdapter.run()
  ↓
Process() (ONLY place)
```

---

## 📋 Phases 2-7 Overview

### Phase 2: Collapse Planner (Single Entry Point)
- **Status:** Not started
- **Scope:** Remove PlannerFacade, make MainPlanner internal, ensure RuntimeOrchestrator is only caller
- **Impact:** One planner.plan() surface, no multi-headed reasoning

### Phase 3: Remove Hidden State Construction
- **Status:** Not started
- **Scope:** Audit for `ServiceName()` defaults, all state from RuntimeBootstrap
- **Impact:** No stateful service injection leaks

### Phase 4: Route File Mutations Through Executor
- **Status:** Partial (FileMutationSpec in place, but some direct writes remain)
- **Scope:** All file write calls → `.file(FileMutationSpec)` commands
- **Impact:** All file ops in event log, auditable mutations

### Phase 5: Compile-Time Guards + Assertions
- **Status:** Not started
- **Scope:** Shadow Process in critical modules, add runtime preconditions
- **Impact:** Impossible to bypass executor (compiler catches it)

### Phase 6: Strengthen Commit Durability
- **Status:** Not started
- **Scope:** Add fsync/flush, determinism test
- **Impact:** Crash safety, provably identical replays

### Phase 7: Remove Transitional Artifacts
- **Status:** Not started
- **Scope:** Delete unused planner variants, legacy memory paths
- **Impact:** No alternate code paths exist

---

## 🎯 What "Done" Actually Means

After all 7 phases:

- ✅ **No `.shell` anywhere** - Not even in legacy code
- ✅ **No Process() outside WorkspaceRunner** - Compile-time guarantee
- ✅ **Planner has one entry** - RuntimeOrchestrator calls `planner.plan()`
- ✅ **No stateful default construction** - All injection from bootstrap
- ✅ **All file changes through executor** - Every mutation in event log
- ✅ **CommitCoordinator is only authority** - No direct state writes
- ✅ **Tests prove it** - Governance tests verify boundaries

---

## 🔧 What Needs Immediate Attention

### High Priority
1. **Fix CLI tools (Phase 1 remainder)** - Route ProcessID creation through RuntimeOrchestrator
2. **Phase 2: Collapse planner** - Remove multi-headed reasoning surface
3. **Add Phase 1 tests** - Verify no `.shell`, no direct Process()

### Medium Priority
1. Phase 3-4: State construction and file mutations
2. Phase 5: Compile-time guards

### Integration
- After Phase 1 + 2 are solid, phases 3-7 can proceed in parallel

---

## Testing Checklist (Phase 1 Validation)

```bash
# Should return 0 results (no `.shell` anywhere):
grep -r "case \.shell" Sources/OracleOS --include="*.swift"

# Should return only DefaultProcessAdapter:
grep -r "= Process()" Sources/OracleOS --include="*.swift" | grep -v DefaultProcessAdapter

# Should show routers calling typed methods:
grep -r "runBuild\|runTest\|runGit\|applyFile" Sources/OracleOS --include="*.swift"

# Should show PolicyEngine accepting all typed commands:
grep -r "\.build, \.test, \.git, \.file" Sources/OracleOS --include="*.swift"
```

---

## Summary

**Phase 1 is ~90% complete.** The core command payload has been restructured from a shell escape hatch into typed, domain-specific operations. Routers have been updated to handle typed specs. WorkspaceRunner now has method signatures for each operation type.

**The remaining 10%** is routing CLI tools through the same controlled path instead of direct Process() calls.

**After Phase 1 is 100% done:** There is no shell execution model left in the domain. Every build, test, git, or file operation goes through a specific command type with a specific spec, validated by policy, routed by domain-specific handlers, executed by WorkspaceRunner methods, and ultimately isolated to DefaultProcessAdapter.

This closes the execution boundary. Phase 2 will collapse the planner surface and ensure single-authority decision-making.
