import re

files_to_fix = [
    ('Sources/oracle/Doctor.swift', [
        ('let spec = BuildSpec(workspacePath: "/", toolchain: .shell, arguments: ["-c", command])', 'let spec = BuildSpec(workspaceRoot: "/", extraArgs: ["-c", command])')
    ]),
    ('Sources/oracle/SetupWizard.swift', [
        ('let spec = BuildSpec(workspacePath: "/", toolchain: .shell, arguments: ["-c", command])', 'let spec = BuildSpec(workspaceRoot: "/", extraArgs: ["-c", command])'),
        ('let spec = BuildSpec(workspacePath: "/", toolchain: .shell, arguments: args)', 'let spec = BuildSpec(workspaceRoot: "/", extraArgs: args)')
    ])
]

for file, replacements in files_to_fix:
    with open(file, 'r') as f:
        content = f.read()

    for old, new in replacements:
        content = content.replace(old, new)

    with open(file, 'w') as f:
        f.write(content)
