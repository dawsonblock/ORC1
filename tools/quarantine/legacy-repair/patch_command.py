import re
import os

path = "Sources/OracleOS/Core/Command/Command.swift"
with open(path, "r") as f:
    text = f.read()

# 1. Remove the kinds switch cases
kind_removals = [
    r'\s*case \.diagnostic\(.*?return "diagnostic"',
    r'\s*case \.envSetup\(.*?return "envSetup"',
    r'\s*case \.hostService\(.*?return "hostService"',
    r'\s*case \.inference\(.*?return "inference"'
]
for pattern in kind_removals:
    text = re.sub(pattern, "", text, flags=re.DOTALL)

# 2. Remove the enum cases in CommandPayload
payload_removals = [
    r'\s*case diagnostic\(DiagnosticSpec\)',
    r'\s*case envSetup\(EnvSetupSpec\)',
    r'\s*case hostService\(HostServiceSpec\)',
    r'\s*case inference\(InferenceSpec\)'
]
for pattern in payload_removals:
    text = re.sub(pattern, "", text)

# 3. Remove the struct definitions
struct_removals = [
    r'public struct DiagnosticSpec.*?\}',
    r'public struct EnvSetupSpec.*?\}',
    r'public struct HostServiceSpec.*?\}',
    r'public struct InferenceSpec.*?\}'
]
for pattern in struct_removals:
    text = re.sub(pattern, "", text, flags=re.DOTALL)

with open(path, "w") as f:
    f.write(text)
