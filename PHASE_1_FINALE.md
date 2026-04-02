# Phase 1 Finale: CLI Tool Routing (Minimal)

Complete Phase 1 by routing CLI tools through RuntimeOrchestrator instead of direct Process() calls.

## Files to Update

### 1. SetupWizard.swift
**Location:** `Sources/oracle/SetupWizard.swift`

**Pattern to replace:**
```swift
// OLD:
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
process.arguments = ["build"]
try process.run()
process.waitUntilExit()

// NEW:
let command = Command(
    type: .code,
    payload: .build(BuildSpec(workspaceRoot: workspaceRoot)),
    metadata: CommandMetadata(intentID: UUID())
)
let outcome = try await executor.execute(command)
guard outcome.status == .success else { throw SetupError.buildFailed }
```

**Minimal change:** 
- Inject `VerifiedExecutor` into SetupWizard init
- Replace direct Process() with Command construction and executor.execute()

### 2. Doctor.swift
**Location:** `Sources/oracle/Doctor.swift`

**Same pattern:**
```swift
// OLD:
let process = Process()
process.executableURL = ...
try process.run()

// NEW:
let command = Command(...)
let outcome = try await executor.execute(command)
```

**Minimal change:**
- Inject VerifiedExecutor
- Replace Process() with Command + executor.execute()

### 3. HostProcessClient.swift
**Location:** `Sources/OracleController/HostProcessClient.swift`

**Pattern:**
```swift
// OLD:
let process = Process()
process.standardOutput = pipe
process.standardError = pipe

// NEW:
let command = Command(...)
let outcome = try await executor.execute(command)
let output = outcome.observations.first?.content ?? ""
```

**Note:** If this is for background process management, may need ProcessResult handling.

### 4. CopilotSupport.swift
**Location:** `Sources/OracleControllerHost/CopilotSupport.swift`

**Same routing pattern.**

---

## Implementation Template

For each file, follow this pattern:

```swift
// 1. Add executor property
class SomeClass {
    let executor: VerifiedExecutor
    
    init(executor: VerifiedExecutor) {
        self.executor = executor
    }
}

// 2. Replace Process() construction
func runCommand() async throws {
    // Before:
    // let process = Process()
    // process.executableURL = ...
    // try process.run()
    
    // After:
    let spec: BuildSpec = .init(workspaceRoot: "/path")
    let command = Command(
        type: .code,
        payload: .build(spec),
        metadata: CommandMetadata(intentID: UUID())
    )
    let outcome = try await executor.execute(command)
    
    guard outcome.status == .success else {
        throw YourError.failed(outcome.status.description)
    }
}
```

---

## Validation After Changes

```bash
# Should return 0 (no direct Process() outside DefaultProcessAdapter):
grep -r "= Process()" Sources --include="*.swift" | \
  grep -v DefaultProcessAdapter | \
  grep -v "// MARK" | \
  wc -l

# Should return > 0 (CLI tools use executor):
grep -r "executor.execute(command" Sources/oracle Sources/OracleController --include="*.swift" | wc -l

# Should return 0 (no .shell anywhere):
grep -r "case \.shell" Sources --include="*.swift" | wc -l
```

---

## Commit Message

```
feat: close execution boundary in Phase 1

- Remove .shell from CommandPayload enum
- Add typed specs: BuildSpec, TestSpec, GitSpec, FileMutationSpec
- Update routers to handle typed commands
- Convert WorkspaceRunner to typed methods
- Route CLI tools through RuntimeOrchestrator

After this commit:
- No shell model exists in the domain
- All process execution routes through one path
- All commands are typed, validated, and deterministic

Closes Phase 1: Execution Boundary
```

---

## Phase 1 Complete Checklist

- [ ] All 4 CLI files updated to route through executor
- [ ] No direct `Process()` calls outside DefaultProcessAdapter
- [ ] `grep -r "case \.shell"` returns 0 results
- [ ] All routers call typed WorkspaceRunner methods
- [ ] PolicyEngine validates by payload type
- [ ] Tests added for boundary enforcement
- [ ] Documentation updated
- [ ] Compile succeeds

---

## What This Achieves

After Phase 1 is 100% complete:

```
✅ Single entry: RuntimeOrchestrator.submitIntent()
✅ Single planner surface: Planner.plan()
✅ Single execution: VerifiedExecutor.execute()
✅ Single mutation: CommitCoordinator.commit()
✅ Single process gate: DefaultProcessAdapter (only place Process() exists)
```

No bypass exists. Enforcement is by type system.

This is the foundation for Phases 2-7.
