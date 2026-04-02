with open('Sources/OracleOS/Planning/MainPlanner.swift', 'r') as f:
    text = f.read()

text = text.replace('        memoryStore: UnifiedMemoryStore,\n        memoryStore: UnifiedMemoryStore,', '        memoryStore: UnifiedMemoryStore,')
with open('Sources/OracleOS/Planning/MainPlanner.swift', 'w') as f:
    f.write(text)

