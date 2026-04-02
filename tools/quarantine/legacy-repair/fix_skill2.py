import re
path = "Sources/OracleOS/Code/Skills/CodeSkillSupport.swift"
with open(path, "r") as f:
    code = f.read()

code = code.replace(
    "static func repositorySnapshot(state: WorldState, workspaceRoot: URL) throws -> RepositorySnapshot {",
    "static func repositorySnapshot(state: WorldState, workspaceRoot: URL, repositoryIndexer: RepositoryIndexer) throws -> RepositorySnapshot {"
)

with open(path, "w") as f:
    f.write(code)

