import re

files_to_fix = [
    "Sources/OracleOS/Execution/Routing/CodeRouter.swift",
    "Sources/OracleOS/Execution/Routing/SystemRouter.swift",
    "Sources/OracleOS/Execution/VerifiedExecutor.swift",
    "Sources/OracleOS/Intent/Policies/PolicyEngine.swift"
]

for file in files_to_fix:
    with open(file, "r") as f:
        content = f.read()

    # VerifiedExecutor
    content = content.replace("case .build, .test, .git, .file, .ui, .code, .diagnostic, .envSetup, .hostService, .inference:", "case .build, .test, .git, .file, .ui, .code:")
    
    # CodeRouter
    content = re.sub(r'case \.diagnostic, \.envSetup, \.hostService, \.inference:[\s\S]*?return CommandRouter\.failureOutcome[\s\S]*?router: "code"\)', '', content)
    
    # SystemRouter
    content = re.sub(r'case \.diagnostic\(let spec\):[\s\S]*?case \.inference\(let spec\):[\s\S]*?\} \(error\.localizedDescription\)"\)\n\s*\}', '', content)

    # PolicyEngine
    content = re.sub(r'case \.diagnostic:[\s\S]*?case \.inference:[\s\S]*?return ActionIntent\([\s\S]*?postconditions: \[\]\)', '', content)

    with open(file, "w") as f:
        f.write(content)
