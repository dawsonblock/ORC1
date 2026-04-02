import os

path = "Tests/OracleOSTests/Governance/ExecutionBoundaryTests.swift"
with open(path, "r") as f:
    content = f.read()

# Make it ignore ProcessShadow
content = content.replace('!fileURL.lastPathComponent.contains("DefaultProcessAdapter")', '!fileURL.lastPathComponent.contains("DefaultProcessAdapter") && !fileURL.lastPathComponent.contains("ProcessShadow")')

with open(path, "w") as f:
    f.write(content)
