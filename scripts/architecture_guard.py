#!/usr/bin/env python3
"""Architecture guard for Oracle-OS.

Scans a narrow set of live authority files for boundary drift that the repo
already claims is forbidden in source comments and governance tests.

This guard intentionally stays small:
- explicit relative file paths only
- required markers for single-authority entry points
- forbidden markers for split-authority regressions
"""

import re
import sys

RULES = {
    "Sources/OracleOS/Execution/Loop/AgentLoop.swift": {
        "forbidden": [
            (
                "WorkflowSynthesizer",
                "AgentLoop must not absorb workflow synthesis internals",
            ),
            (
                "PatchRanker",
                "AgentLoop must not absorb experiment ranking internals",
            ),
            ("DOMIndexer", "AgentLoop must not absorb DOM indexing internals"),
            (
                "BrowserTargetResolver",
                "AgentLoop must not absorb browser target resolution "
                "internals",
            ),
            (
                "MemoryPromotionPolicy",
                "AgentLoop must not absorb memory promotion internals",
            ),
            (
                "MemoryScorer",
                "AgentLoop must not absorb memory scoring internals",
            ),
        ],
        "required": [
            (
                "IntentAPI",
                "AgentLoop must stay wired to the runtime through IntentAPI",
            ),
        ],
    },
    "Sources/OracleOS/Planning/Planner.swift": {
        "forbidden": [
            (
                "VerifiedExecutor",
                "Planner contract must not reference execution authority",
            ),
            (
                "CommandRouter",
                "Planner contract must not reference routing authority",
            ),
            (
                "DefaultProcessAdapter",
                "Planner contract must not reference shell adapters",
            ),
            ("Process()", "Planner contract must not spawn raw processes"),
            (
                "Foundation.Process()",
                "Planner contract must not spawn raw processes",
            ),
            ("Actions.", "Planner contract must not import execution actions"),
        ],
        "required": [
            (
                "func plan(intent:",
                "Planner contract must remain command-producing only",
            ),
        ],
    },
    "Sources/OracleOS/Planning/MainPlanner.swift": {
        "forbidden": [
            (
                "VerifiedExecutor",
                "MainPlanner must not execute commands directly",
            ),
            ("CommandRouter", "MainPlanner must not route commands directly"),
            (
                "DefaultProcessAdapter",
                "MainPlanner must not create shell adapters",
            ),
            ("Process()", "MainPlanner must not spawn raw processes"),
            (
                "Foundation.Process()",
                "MainPlanner must not spawn raw processes",
            ),
            (
                "commitCoordinator.commit(",
                "MainPlanner must not commit events directly",
            ),
            (
                "eventStore.append(",
                "MainPlanner must not append events directly",
            ),
            ("Actions.", "MainPlanner must not execute UI actions directly"),
        ],
        "required": [
            ("TaskLedger", "MainPlanner must remain task-ledger based"),
        ],
    },
    "Sources/OracleOS/Runtime/RuntimeBootstrap.swift": {
        "forbidden": [
            (
                "RuntimeContext(",
                "RuntimeBootstrap must not reintroduce RuntimeContext as a "
                "live runtime dependency",
            ),
            (
                "WaitManager.waitFor(",
                "Wait bypass belongs only in ControllerRuntimeBridge",
            ),
        ],
        "exact_count": [
            (
                "VerifiedExecutor(",
                1,
                "RuntimeBootstrap must assemble exactly one VerifiedExecutor",
            ),
            (
                "CommitCoordinator(",
                1,
                "RuntimeBootstrap must assemble exactly one "
                "CommitCoordinator for supported-path mutation authority",
            ),
            (
                "CommandRouter(",
                1,
                "RuntimeBootstrap must assemble exactly one CommandRouter "
                "for the supported spine",
            ),
            (
                "MainPlanner(",
                1,
                "RuntimeBootstrap must assemble exactly one MainPlanner "
                "for the supported spine",
            ),
            (
                "RuntimeOrchestrator(container: container)",
                1,
                "RuntimeBootstrap must assemble exactly one "
                "RuntimeOrchestrator from the canonical container",
            ),
            (
                "RuntimeContainer(",
                1,
                "RuntimeBootstrap must assemble exactly one RuntimeContainer",
            ),
        ],
    },
    "Sources/OracleOS/Runtime/RuntimeOrchestrator.swift": {
        "forbidden": [
            (
                "eventStore.append(",
                "RuntimeOrchestrator must not append events directly",
            ),
        ],
        "required": [
            (
                "container.planner.plan(",
                "RuntimeOrchestrator must keep planning inside the "
                "supported spine",
            ),
            (
                "container.executor.execute(",
                "RuntimeOrchestrator must keep verified execution inside "
                "the supported spine",
            ),
            (
                "container.commitCoordinator.commit(",
                "RuntimeOrchestrator must keep durable mutation "
                "centralized in CommitCoordinator",
            ),
        ],
    },
    "Sources/OracleOS/Runtime/RuntimeExecutionDriver.swift": {
        "forbidden": [
            (
                "VerifiedExecutor(",
                "RuntimeExecutionDriver must submit through IntentAPI, "
                "not call the executor directly",
            ),
            (
                "CommandRouter(",
                "RuntimeExecutionDriver must not route commands directly",
            ),
            (
                "DefaultProcessAdapter(",
                "RuntimeExecutionDriver must not create shell adapters",
            ),
            (
                "Process()",
                "RuntimeExecutionDriver must not spawn raw processes",
            ),
            (
                "Foundation.Process()",
                "RuntimeExecutionDriver must not spawn raw processes",
            ),
            (
                "commitCoordinator.commit(",
                "RuntimeExecutionDriver must not commit events directly",
            ),
        ],
        "required": [
            (
                "submitIntent(",
                "RuntimeExecutionDriver must route execution through "
                "submitIntent",
            ),
        ],
    },
    "Sources/OracleControllerHost/ControllerRuntimeBridge.swift": {
        "forbidden": [
            (
                "planner.nextStep(",
                "Controller bridge must not call planners directly",
            ),
            (
                "planner.plan(",
                "Controller bridge must not call planners directly",
            ),
            (
                "VerifiedExecutor(",
                "Controller bridge must not construct the executor",
            ),
            (
                "verifiedExecutor.execute(",
                "Controller bridge must not execute through the executor "
                "directly",
            ),
            (
                "commandRouter.execute(",
                "Controller bridge must not route commands directly",
            ),
            (
                "commitCoordinator.commit(",
                "Controller bridge must not commit events directly",
            ),
            (
                "eventStore.append(",
                "Controller bridge must not append events directly",
            ),
            (
                "RuntimeContext(",
                "Controller bridge must not store RuntimeContext authority",
            ),
            (
                '"mcpServers"] as? [String: Any]',
                "Controller bridge health checks must not probe Claude "
                "config through raw dictionaries",
            ),
        ],
        "exact_count": [
            (
                "makeBootstrappedRuntime(",
                1,
                "Controller bridge must bootstrap exactly one runtime "
                "entrypoint",
            ),
            (
                "WaitManager.waitFor(",
                1,
                "Controller bridge must keep a single explicit "
                "WaitManager bypass",
            ),
            (
                "container.automationHost.snapshots.captureSnapshot(",
                1,
                "AutomationHost usage in the controller bridge must "
                "remain observational-only",
            ),
        ],
    },
    "Sources/OracleControllerHost/ControllerRuntimeBridge+Mapping.swift": {
        "forbidden": [
            (
                "result.data?[ActionResultKey.actionResult]",
                "Controller bridge mapping must not reintroduce nested "
                "action_result dictionary probing",
            ),
            (
                "result.data?[ActionResultKey.codeExecution]",
                "Controller bridge mapping must not reintroduce nested "
                "code_execution dictionary probing",
            ),
            (
                "data[RecipeResultKey.stepResults] as? [[String: Any]]",
                "Controller bridge mapping must not rebuild recipe "
                "results from nested step-result dictionaries",
            ),
            (
                "actionData?[ActionResultKey.policyDecision]",
                "Controller bridge mapping must not read policy state "
                "from nested dictionary payloads",
            ),
            (
                "func recipeDictionary(",
                "Controller bridge mapping must not rebuild Recipe "
                "values through manual JSON dictionaries",
            ),
            (
                "func waitDictionary(",
                "Controller bridge mapping must not rebuild Recipe wait "
                "conditions through manual JSON dictionaries",
            ),
            (
                "func locatorDictionary(",
                "Controller bridge mapping must not rebuild Locator "
                "values through manual JSON dictionaries",
            ),
            (
                "loadClaudeConfig() -> [String: Any]?",
                "Controller bridge mapping must not expose Claude config "
                "as a raw dictionary",
            ),
            (
                'data["image"] as? String',
                "Controller bridge mapping must not manually probe "
                "screenshot payload dictionaries",
            ),
        ],
        "required": [
            (
                "result.actionResult",
                "Controller bridge mapping must use typed action results "
                "on the live boundary",
            ),
            (
                "result.recipeRunResult",
                "Controller bridge mapping must use typed recipe results "
                "on the live boundary",
            ),
            (
                "result.screenshotResult",
                "Controller bridge mapping must use typed screenshot "
                "payloads on the live boundary",
            ),
        ],
    },
}


def strip_comments(content: str) -> str:
    content = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    lines = []
    for line in content.splitlines():
        if "//" in line:
            line = line.split("//", 1)[0]
        lines.append(line)
    return "\n".join(lines)


def scan_repo():
    violations = []

    for path, rule in RULES.items():
        try:
            with open(path, encoding="utf-8") as fh:
                content = fh.read()
        except FileNotFoundError:
            violations.append((path, ["required file missing"]))
            continue

        source = strip_comments(content)
        file_violations = []

        for pattern, message in rule.get("required", []):
            if pattern not in source:
                file_violations.append(
                    f"missing required marker '{pattern}': {message}"
                )

        for pattern, expected_count, message in rule.get("exact_count", []):
            actual_count = source.count(pattern)
            if actual_count != expected_count:
                file_violations.append(
                    f"expected {expected_count} occurrence(s) of '{pattern}', "
                    f"found {actual_count}: {message}"
                )

        for pattern, message in rule.get("forbidden", []):
            if pattern in source:
                file_violations.append(
                    f"forbidden marker '{pattern}': {message}"
                )

        if file_violations:
            violations.append((path, file_violations))

    return violations


if __name__ == "__main__":
    violations = scan_repo()

    if violations:
        print("\nARCHITECTURE VIOLATIONS FOUND\n")
        print(
            "Architecture contract drifted: the supported spine must remain "
            "RuntimeBootstrap -> RuntimeOrchestrator -> MainPlanner -> "
            "VerifiedExecutor -> CommandRouter -> UIRouter / CodeRouter -> "
            "CommitCoordinator. Update code and contract together.\n"
        )

        for path, items in violations:
            print(path)
            for item in items:
                print("  issue:", item)

        sys.exit(1)

    print("Architecture guard passed.")
