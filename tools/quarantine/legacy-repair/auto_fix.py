import os

def read_file(path):
    with open(path, 'r') as f:
        return f.read()

def write_file(path, content):
    with open(path, 'w') as f:
        f.write(content)

content = read_file('Tests/OracleOSTests/TestCompatibility/TestAPICompatibility.swift')
content = content.replace('-> WorkflowMatch?', '-> ParameterizedWorkflow?')
content = content.replace('func retrieve(\n        goal: Goal,\n        taskContext: TaskContext,\n        worldState: WorldState,\n        workflowIndex: WorkflowIndex\n    ) -> ParameterizedWorkflow?', 'func retrieve(\n        goal: Goal,\n        taskContext: TaskContext,\n        worldState: WorldState,\n        workflowIndex: WorkflowIndex\n    ) -> WorkflowMatch?')

parts = content.split('extension PatchExperimentRunner {')
if len(parts) > 2:
    content = parts[0] + 'extension PatchExperimentRunner {' + parts[1]
write_file('Tests/OracleOSTests/TestCompatibility/TestAPICompatibility.swift', content)

content = read_file('Tests/OracleOSTests/CodeIntelligence/PatchTargetSelectionTests.swift')
content = content.replace('ExperimentResultRanker()', 'ExperimentResultRanker(patchRanker: PatchRanker(comparator: ResultComparator()))')
write_file('Tests/OracleOSTests/CodeIntelligence/PatchTargetSelectionTests.swift', content)

content = read_file('Tests/OracleOSTests/Strategy/StrategyScopedWorkflowTests.swift')
content = content.replace('workflowIndex: WorkflowIndex(),\n            selectedStrategy: repoStrategy', 
    'workflowIndex: WorkflowIndex(),\n            memoryStore: UnifiedMemoryStore(appMemory: StrategyMemory()),\n            selectedStrategy: repoStrategy')
write_file('Tests/OracleOSTests/Strategy/StrategyScopedWorkflowTests.swift', content)

content = read_file('Tests/OracleOSTests/Planning/PlannerPlanSelectionTests.swift')
content = content.replace('MainPlanner(reasoningThreshold: 0)', 'MainPlanner(workflowIndex: WorkflowIndex(), reasoningThreshold: 0)')
content = content.replace('MainPlanner(reasoningThreshold: 0.25)', 'MainPlanner(workflowIndex: WorkflowIndex(), reasoningThreshold: 0.25)')
write_file('Tests/OracleOSTests/Planning/PlannerPlanSelectionTests.swift', content)

content = read_file('Tests/OracleOSTests/Experiments/PatchExperimentRunnerTests.swift')
content = content.replace('snapshot: nil', 'snapshot: nil as RepositorySnapshot?')
write_file('Tests/OracleOSTests/Experiments/PatchExperimentRunnerTests.swift', content)
