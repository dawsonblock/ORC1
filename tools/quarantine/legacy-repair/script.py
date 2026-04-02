import os
path = "Sources/OracleOS/Code/Skills/CodeSkillSupport.swift"
with open(path, "r") as f:
    code = f.read()

code = code.replace("repositorySnapshot(state: WorldState, workspaceRoot: URL, repositoryIndexer: RepositoryIndexer)", "repositorySnapshot(state: WorldState, workspaceRoot: URL)")
code = code.replace("return repositoryIndexer.indexIfNeeded(workspaceRoot: workspaceRoot)", "throw CodeSkillResolutionError.noRepositorySnapshot")
code = code.replace("let snapshot = try repositorySnapshot(state: state, workspaceRoot: workspaceRoot, repositoryIndexer: repositoryIndexer)", "let snapshot = try repositorySnapshot(state: state, workspaceRoot: workspaceRoot)")

with open(path, "w") as f:
    f.write(code)

for filename in ["WriteFileSkill.swift", "EditFileSkill.swift", "GeneratePatchSkill.swift", "OpenFileSkill.swift"]:
    p = f"Sources/OracleOS/Code/Skills/{filename}"
    if not os.path.exists(p): continue
    with open(p, "r") as f:
        code = f.read()
    code = code.replace(", repositoryIndexer: repositoryIndexer", "")
    code = code.replace(", repositoryIndexer", "")
    with open(p, "w") as f:
        f.write(code)

