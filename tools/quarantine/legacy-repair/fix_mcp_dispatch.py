import re
path = "Sources/OracleOS/MCP/MCPDispatch.swift"
with open(path, "r") as f:
    code = f.read()

code = code.replace("import Foundation", "import Foundation\nimport Dispatch")

with open(path, "w") as f:
    f.write(code)
