import re
path = "Sources/OracleOS/Planning/Reasoning/PlanGenerator.swift"
with open(path, "r") as f:
    code = f.read()

code = code.replace("        codePlanner: CodePlanner? = nil,", "        codePlanner: CodePlanner,")
code = code.replace("""        self.codePlanner = codePlanner ?? CodePlanner(
            graphPlanner: sharedGraphPlanner,
            workflowIndex: sharedWorkflowIndex,
            workflowRetriever: sharedWorkflowRetriever,
            workflowExecutor: sharedWorkflowExecutor
        )""", "        self.codePlanner = codePlanner")

with open(path, "w") as f:
    f.write(code)
