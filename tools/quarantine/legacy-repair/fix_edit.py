with open('Sources/OracleOS/Code/Skills/EditFileSkill.swift', 'r') as f:
    text = f.read()
text = text.replace('intent: .code(name: "Edit file", command: command, workspaceRelativePath: path),', 'intent: .code(name: "Edit file", command: command, workspaceRelativePath: path, text: taskContext.goal.description),')
with open('Sources/OracleOS/Code/Skills/EditFileSkill.swift', 'w') as f:
    f.write(text)
