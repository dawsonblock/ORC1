import re
path = "Sources/OracleOS/Code/Skills/CodeSkillSupport.swift"
with open(path, "r") as f:
    code = f.read()

code = code.replace("RepositoryIndexer().indexIfNeeded(", "repositoryIndexer.indexIfNeeded(")

with open(path, "w") as f:
    f.write(code)
