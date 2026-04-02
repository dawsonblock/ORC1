import re

path = "Sources/OracleOS/Planning/MainPlanner.swift"
with open(path, "r") as f:
    code = f.read()

code = code.replace("memoryStore: UnifiedMemoryStore = UnifiedMemoryStore(),", "memoryStore: UnifiedMemoryStore,")

with open(path, "w") as f:
    f.write(code)
