# Oracle OS Eval Harness

This directory contains small, deterministic eval fixtures for planner, recovery,
and workflow logic. These are synthetic in-process scenarios, not full end-to-end
runtime benchmarks against a live app or repository.

Live files in this directory:

- `UpgradeBenchmarks.swift`
  - bounded multi-step plan generation
  - modal recovery planning
  - workflow confidence / reuse checks
- `DialogStormTasks.swift`
  - sequential dialog recovery fixtures
  - repeated modal interruption handling
- `PatchFailureTasks.swift`
  - wrong-file patch recovery fixture
  - build-break recovery fixture
  - test-regression recovery fixture

Shared harness files:

- `EvalTask.swift`
  - task family definitions and per-run snapshot contract
- `EvalRunner.swift`
  - runs repeated synthetic tasks and computes metrics
- `EvalMetrics.swift`
  - shared metric calculations and regression formatting
- `EvalReport.swift`
  - result envelope for a completed task run
- `EvalTestCompatibility.swift`
  - compatibility shims for the test surface

Primary metrics:

- `success_rate`
- `first_pass_success_rate`
- `average_steps`
- `recovery_success_rate`
- `graph_reuse_ratio`
- `workflow_reuse_ratio`
- `ambiguity_failure_count`
- `patch_selection_success_rate`
- `recovery_reuse_ratio`
- `planner_reasoning_ratio`
- `plan_stability`
- `wrong_target_rate`
- `recovery_loop_count`

How to run:

```bash
swift test --filter "Upgrade Benchmarks"
swift test --filter "Dialog Storm Tasks"
swift test --filter "Patch Failure Tasks"
swift test
```

How to interpret:

- Treat these as deterministic regression fixtures for planner behavior and metric
  plumbing, not as proof of live desktop or repo repair performance.
- A green result here means the local planning/recovery heuristics behaved as the
  fixture expected.
- Do not describe these files as merge-blocking empirical benchmarks unless a real
  end-to-end harness is added.
