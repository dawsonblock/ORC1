# Single-Hard-Path Runtime: Rebuild Plan

## Completed (Phase 1 u0026 2 - 100% Done)

✅ Created 4 new Spec types:
  - BuildSpec.swift
  - TestSpec.swift  
  - GitSpec.swift
  - FileMutationSpec.swift

✅ Updated CommandPayload enum:
  - Removed `.shell(CommandSpec)`
  - Added `.build(BuildSpec)`, `.test(TestSpec)`, `.git(GitSpec)`, `.file(FileMutationSpec)`

✅ Updated Command.kind property:
  - Removed shell-specific routing

✅ Updated PolicyEngine:
  - Removed `/usr/bin/env` hardcoded allowlist
  - Removed shell-specific policy logic
  - Added typed command routing in `actionIntent(from:)`

---

## Remaining Phases (3-7)

### 1. Update Routers to Handle Typed Commands

**Files to modify:**
- CodeRouter.swift
- SystemRouter.swift
- CommandRouter.swift

**Strategy:**
- Remove `case .shell(let spec)` from all routers
- Add handlers for `.build(BuildSpec)`, `.test(TestSpec)`, `.git(GitSpec)`, `.file(FileMutationSpec)`
- Each handler calls WorkspaceRunner typed methods (see below)

**Example CodeRouter update:**

```swift
case .build(let spec):
    guard let workspaceRunner else { return failureOutcome(...) }
    let result = try await workspaceRunner.runBuild(spec)
    return buildExecutionOutcome(command, result, policyDecision)

case .test(let spec):
    guard let workspaceRunner else { return failureOutcome(...) }
    let result = try await workspaceRunner.runTest(spec)
    return buildExecutionOutcome(command, result, policyDecision)

case .git(let spec):
    guard let workspaceRunner else { return failureOutcome(...) }
    let result = try await workspaceRunner.runGit(spec)
    return buildExecutionOutcome(command, result, policyDecision)

case .file(let spec):
    guard let workspaceRunner else { return failureOutcome(...) }
    try workspaceRunner.applyFile(spec)
    return successOutcome(command, policyDecision)
```

### 2. Convert WorkspaceRunner to Typed Methods

**File:** WorkspaceRunner.swift

**Current:**
```swift
func execute(spec: CommandSpec) async throws -> CommandResult
```

**Target:**
```swift
func runBuild(_ spec: BuildSpec) async throws -> ProcessResult
func runTest(_ spec: TestSpec) async throws -> ProcessResult
func runGit(_ spec: GitSpec) async throws -> ProcessResult
func applyFile(_ spec: FileMutationSpec) async throws
```

**Implementation pattern:**

```swift
func runBuild(_ spec: BuildSpec) async throws -> ProcessResult {
    return try await executeProcess(
        executable: "/usr/bin/swift",
        arguments: ["build"] + buildArgs(spec),
        in: spec.workspaceRoot
    )
}

func runTest(_ spec: TestSpec) async throws -> ProcessResult {
    return try await executeProcess(
        executable: "/usr/bin/swift",
        arguments: ["test"] + testArgs(spec),
        in: spec.workspaceRoot
    )
}

func runGit(_ spec: GitSpec) async throws -> ProcessResult {
    return try await executeProcess(
        executable: "/usr/bin/git",
        arguments: [spec.operation.rawValue] + spec.args,
        in: spec.workspaceRoot
    )
}

func applyFile(_ spec: FileMutationSpec) async throws {
    let url = URL(fileURLWithPath: spec.path)
    switch spec.operation {
    case .write:
        try spec.content?.write(to: url, atomically: true, encoding: .utf8)
    case .delete:
        try FileManager.default.removeItem(at: url)
    case .append:
        // ... append logic
    }
}

private func executeProcess(
    executable: String,
    arguments: [String],
    in workspace: String
) async throws -> ProcessResult {
    // Delegate to DefaultProcessAdapter (internal only)
}

// Helper methods for spec → args conversion
private func buildArgs(_ spec: BuildSpec) -> [String] { [...] }
private func testArgs(_ spec: TestSpec) -> [String] { [...] }
```

### 3. Eliminate Direct Process() Usage

**Files to fix:**
- Sources/oracle/SetupWizard.swift
- Sources/oracle/Doctor.swift
- Sources/OracleController/HostProcessClient.swift
- Sources/OracleControllerHost/CopilotSupport.swift

**Rule:** All Process() instantiation must go through:
```
VerifiedExecutor → CommandRouter → Router → WorkspaceRunner → DefaultProcessAdapter
```

**For CLI tools (oracle CLI):**
Instead of direct Process(), use RuntimeOrchestrator.submitIntent():

```swift
// Before:
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
process.arguments = ["build"]
try process.run()

// After:
let intent = Intent(objective: "build the project")
let command = Command(type: .code, payload: .build(BuildSpec(workspaceRoot: ".")))
let outcome = try await executor.execute(command)
```

---

## Phases 2-7 Overview (Remaining Work)

**Phase 2: Collapse Planner (Single Entry Point)**
- Remove PlannerFacade.swift (duplicate abstraction)
- Convert MainPlanner → internal PlannerEngine
- Ensure only RuntimeOrchestrator calls planner.plan()

**Phase 3: Remove Hidden State Construction**
- Audit all stateful objects: no `ServiceName()` defaults
- All state must come from RuntimeBootstrap → RuntimeContainer

**Phase 4: Route File Mutations Through Executor**
- All `write()`, `delete()` calls → .file(FileMutationSpec) commands
- Emit FileModified events for reducers

**Phase 5: Compile-Time Guards + Runtime Assertions**
- Shadow Process in critical modules
- Add preconditions in VerifiedExecutor
- Add test assertions for execution boundary

**Phase 6: Strengthen Commit Durability**
- Add fsync/flush in EventStore.append()
- Add determinism test (same input → identical sequence)

**Phase 7: Remove Transitional Artifacts**
- Delete legacy planner variants
- Remove "experimental" memory paths
- No alternate code paths exist

---

## Testing Strategy

**For Phase 1:**
Add to Tests/OracleOSTests/Governance/:

```swift
func testNoShellPayloadExists() {
    // Verify CommandPayload.shell never appears in codebase
    // grep Sources -r "case .shell" → 0 results
}

func testAllProcessUsageRouted() {
    // Verify no Process() outside WorkspaceRunner
    // grep -r "= Process()" → only DefaultProcessAdapter
}

func testTypedCommandsOnly() {
    // Verify command creation uses .build, .test, .git, .file only
}
```

---

## Merge Strategy

**Milestone 1 (Phase 1):** Close execution boundary
- No .shell anywhere
- All typed commands
- All Process() routed

**Milestone 2 (Phase 2):** Single planner entry
- One Planner.plan() surface
- RuntimeOrchestrator only caller

**Milestone 3 (Phase 3-4):** No hidden state, file mutations typed
- No default service construction
- All file ops go through executor

**Milestone 4 (Phase 5-7):** Enforcement + cleanup
- Compile-time guards
- Remove alternate paths
- Tests prove boundary enforcement

---

## Why This Matters

After Phase 1-2, you have:
- **Deterministic:** Typed commands only, no string escapes
- **Enforced:** No execution path exists outside VerifiedExecutor
- **Auditable:** All side effects in event log
- **Single-path:** One spine from Intent → Command → Execute → Commit

This is a real agent kernel, not a sandbox facade.
