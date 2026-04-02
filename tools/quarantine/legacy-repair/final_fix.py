import re

with open('Sources/OracleOS/Planning/MainPlanner+Planner.swift', 'r') as f:
    code = f.read()

replacement = """        // Note: actionIntent.codeCommand is a deprecated field. New code should use typed specs.
        if let codeCommand = actionIntent.codeCommand {
            let workspace = codeCommand.workspaceRoot
            let path = codeCommand.workspaceRelativePath ?? ""
            let content = actionIntent.text
            
            switch codeCommand.category {
            case .build:
                let spec = BuildSpec(workspaceRoot: workspace)
                return Command(type: .code, payload: .build(spec), metadata: metadata)
            case .test:
                let spec = TestSpec(workspaceRoot: workspace)
                return Command(type: .code, payload: .test(spec), metadata: metadata)
            case .editFile, .writeFile, .generatePatch:
                let spec = FileMutationSpec(path: path, operation: .write, content: content, workspaceRoot: workspace)
                return Command(type: .code, payload: .file(spec), metadata: metadata)
            case .gitStatus:
                let spec = GitSpec(operation: .status, args: codeCommand.arguments, workspaceRoot: workspace)
                return Command(type: .code, payload: .git(spec), metadata: metadata)
            case .gitCommit:
                let spec = GitSpec(operation: .commit, args: codeCommand.arguments, workspaceRoot: workspace)
                return Command(type: .code, payload: .git(spec), metadata: metadata)
            case .gitBranch:
                let spec = GitSpec(operation: .branch, args: codeCommand.arguments, workspaceRoot: workspace)
                return Command(type: .code, payload: .git(spec), metadata: metadata)
            case .gitPush:
                let spec = GitSpec(operation: .push, args: codeCommand.arguments, workspaceRoot: workspace)
                return Command(type: .code, payload: .git(spec), metadata: metadata)
            case .openFile:
                let action = CodeAction(name: "readFile", filePath: path, workspacePath: workspace)
                return Command(type: .code, payload: .code(action), metadata: metadata)
            case .searchCode, .indexRepository:
                let action = CodeAction(name: "searchRepository", query: codeCommand.summary, workspacePath: workspace)
                return Command(type: .code, payload: .code(action), metadata: metadata)
            default:
                let action = CodeAction(name: codeCommand.category.rawValue, query: codeCommand.summary, workspacePath: workspace)
                return Command(type: .code, payload: .code(action), metadata: metadata)
            }
        }

        let modifiers:"""

pattern = r"\s*// Note: actionIntent\.codeCommand is a deprecated field.*?let modifiers:"
code = re.sub(pattern, replacement, code, flags=re.DOTALL)

with open('Sources/OracleOS/Planning/MainPlanner+Planner.swift', 'w') as f:
    f.write(code)
