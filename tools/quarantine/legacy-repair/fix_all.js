const fs = require('fs');

let f1 = 'Sources/OracleOS/Execution/Routing/CommandRouter.swift';
let t1 = fs.readFileSync(f1, 'utf8');
fs.writeFileSync(f1, t1.replace('repositoryIndexer: RepositoryIndexer = RepositoryIndexer()', 'repositoryIndexer: RepositoryIndexer'));

let f2 = 'Sources/OracleOS/Recovery/RecoveryEngine.swift';
let t2 = fs.readFileSync(f2, 'utf8');
t2 = t2.replace('memoryStore: UnifiedMemoryStore? = nil', 'memoryStore: UnifiedMemoryStore');
t2 = t2.replace('let memoryStore = memoryStore ?? UnifiedMemoryStore()', '');
t2 = t2.replace('let memoryStore = memoryStore', '');
fs.writeFileSync(f2, t2);

let f3 = 'Sources/OracleOS/Planning/Memory/MemoryRouter.swift';
let t3 = fs.readFileSync(f3, 'utf8');
t3 = t3.replace('public init(memoryStore: UnifiedMemoryStore? = nil) {', 'public init(memoryStore: UnifiedMemoryStore) {');
t3 = t3.replace('self.unifiedStore = memoryStore ?? UnifiedMemoryStore()', 'self.unifiedStore = memoryStore');
fs.writeFileSync(f3, t3);

let f4 = 'Sources/OracleOS/Planning/MainPlanner.swift';
let t4 = fs.readFileSync(f4, 'utf8');
t4 = t4.replace(/resolvedCodePlanner = codePlanner \?\? CodePlanner\(/g, 'resolvedCodePlanner = codePlanner ?? CodePlanner(\n            repositoryIndexer: repositoryIndexer,\n            impactAnalyzer: impactAnalyzer,');
t4 = t4.replace(/memoryStore:\s*UnifiedMemoryStore,\n\s*memoryStore:\s*UnifiedMemoryStore/g, 'memoryStore: UnifiedMemoryStore');
fs.writeFileSync(f4, t4);
