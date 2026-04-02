#!/usr/bin/env python3
import os, re, sys
def check():
    path = "Sources/OracleOS/MCP/MCPDispatch.swift"
    if not os.path.exists(path): return False
    with open(path,"r") as f: c = f.read()
    if "func dispatch(request: MCPToolRequest)" not in c: return False
    if "formatTypedResult" not in c: return False
    print("VALID")
    return True
if __name__ == "__main__":
    if not check(): sys.exit(1)
