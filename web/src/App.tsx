import { useState, useEffect } from 'react';
import { 
  Activity, Zap, Shield, RotateCcw, 
  Database, Terminal, Layers
} from 'lucide-react';
import './App.css';

function App() {
  const [metrics, setMetrics] = useState({
    system: { status: 'DEGRADED', mode: 'RECOVERY', uptime: '1h 24m' },
    budget: { steps: 142, stalls: 2, totalTime: '4m 12s', rate: '2.5t/s' },
    policy: { checks: 843, warnings: 12, blocks: 1, mode: 'STRICT' },
    recovery: { attempts: 4, fallback: 1, health: '85%' },
    memory: { size: '4.2MB', schemas: 12, relations: 856, freshness: 'High' }
  });

  // Mock real-time updates for visual effect while backend connects
  useEffect(() => {
    const timer = setInterval(() => {
      setMetrics(prev => ({
        ...prev,
        budget: { ...prev.budget, steps: prev.budget.steps + Math.floor(Math.random() * 3) },
        policy: { ...prev.policy, checks: prev.policy.checks + Math.floor(Math.random() * 5) }
      }));
    }, 2000);
    return () => clearInterval(timer);
  }, []);

  return (
    <div className="min-h-screen bg-slate-950 text-slate-200 p-6 flex flex-col">
      <header className="flex items-center justify-between mb-8 border-b border-slate-800 pb-4">
        <div className="flex items-center gap-3">
          <div className="bg-blue-600 p-2 rounded-lg">
            <Activity className="w-6 h-6 text-white" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-white tracking-tight">Oracle-OS</h1>
            <p className="text-slate-400 text-sm font-medium">System Telemetry & Control</p>
          </div>
        </div>
        
        <div className="flex items-center gap-4 bg-slate-900 rounded-lg px-4 py-2 border border-slate-800 border-l-4 border-l-amber-500">
          <div className="h-3 w-3 rounded-full bg-amber-500 animate-pulse"></div>
          <span className="font-semibold text-amber-500">{metrics.system.status}</span>
          <span className="text-slate-500 text-sm ml-2">({metrics.system.mode})</span>
        </div>
      </header>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-6 flex-1">
        {/* Loop Budget */}
        <section className="bg-slate-900 rounded-xl p-5 border border-slate-800 shadow-xl relative overflow-hidden">
          <div className="absolute top-0 right-0 w-32 h-32 bg-indigo-500/5 rounded-full blur-3xl -mr-10 -mt-10"></div>
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center gap-2 text-indigo-400">
              <Zap className="w-5 h-5" />
              <h2 className="font-semibold text-lg uppercase tracking-wider text-slate-300">Agent Loop</h2>
            </div>
          </div>
          <div className="space-y-4">
            <div className="flex justify-between items-center border-b border-slate-800/50 pb-2">
              <span className="text-slate-500">Total Steps</span>
              <span className="font-mono text-xl font-medium text-slate-200">{metrics.budget.steps}</span>
            </div>
            <div className="flex justify-between items-center border-b border-slate-800/50 pb-2">
              <span className="text-slate-500">Consecutive Stalls</span>
              <span className="font-mono font-medium text-amber-400">{metrics.budget.stalls}</span>
            </div>
            <div className="flex justify-between items-center border-b border-slate-800/50 pb-2">
              <span className="text-slate-500">Execution Time</span>
              <span className="font-mono font-medium text-slate-300">{metrics.budget.totalTime}</span>
            </div>
            <div className="flex justify-between items-center border-b border-slate-800/50 pb-2">
              <span className="text-slate-500">Token Rate</span>
              <span className="font-mono font-medium text-indigo-400">{metrics.budget.rate}</span>
            </div>
          </div>
        </section>

        {/* Policy Engine */}
        <section className="bg-slate-900 rounded-xl p-5 border border-slate-800 shadow-xl relative overflow-hidden">
          <div className="absolute top-0 right-0 w-32 h-32 bg-emerald-500/5 rounded-full blur-3xl -mr-10 -mt-10"></div>
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center gap-2 text-emerald-400">
              <Shield className="w-5 h-5" />
              <h2 className="font-semibold text-lg uppercase tracking-wider text-slate-300">Policy Engine</h2>
            </div>
            <span className="text-xs font-semibold px-2 py-1 bg-emerald-500/10 text-emerald-400 rounded border border-emerald-500/20">{metrics.policy.mode}</span>
          </div>
          <div className="space-y-4">
            <div className="flex justify-between items-center border-b border-slate-800/50 pb-2">
              <span className="text-slate-500">Checks Passed</span>
              <span className="font-mono text-xl font-medium text-emerald-400">{metrics.policy.checks}</span>
            </div>
            <div className="flex justify-between items-center border-b border-slate-800/50 pb-2">
              <span className="text-slate-500">Constraint Warnings</span>
              <span className="font-mono font-medium text-amber-400">{metrics.policy.warnings}</span>
            </div>
            <div className="flex justify-between items-center border-b border-slate-800/50 pb-2">
              <span className="text-slate-500">Hard Blocks</span>
              <span className="font-mono font-medium text-red-400">{metrics.policy.blocks}</span>
            </div>
          </div>
        </section>

        {/* Recovery Stats */}
        <section className="bg-slate-900 rounded-xl p-5 border border-slate-800 shadow-xl relative overflow-hidden">
          <div className="absolute top-0 right-0 w-32 h-32 bg-rose-500/5 rounded-full blur-3xl -mr-10 -mt-10"></div>
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center gap-2 text-rose-400">
              <RotateCcw className="w-5 h-5" />
              <h2 className="font-semibold text-lg uppercase tracking-wider text-slate-300">Recovery</h2>
            </div>
          </div>
          <div className="space-y-4">
            <div className="flex justify-between items-center border-b border-slate-800/50 pb-2">
              <span className="text-slate-500">Total Attempts</span>
              <span className="font-mono text-xl font-medium text-slate-200">{metrics.recovery.attempts}</span>
            </div>
            <div className="flex justify-between items-center border-b border-slate-800/50 pb-2">
              <span className="text-slate-500">Fallback Triggers</span>
              <span className="font-mono font-medium text-amber-400">{metrics.recovery.fallback}</span>
            </div>
            <div className="flex gap-2 flex-col mt-4">
              <div className="flex justify-between text-sm">
                <span className="text-slate-500">System Health</span>
                <span className="font-mono font-medium text-emerald-400">{metrics.recovery.health}</span>
              </div>
              <div className="h-2 w-full bg-slate-800 rounded-full overflow-hidden">
                <div className="h-full bg-gradient-to-r from-emerald-500 to-emerald-400 w-[85%] rounded-full shadow-[0_0_10px_rgba(52,211,153,0.5)]"></div>
              </div>
            </div>
          </div>
        </section>

        {/* Project Memory */}
        <section className="bg-slate-900 rounded-xl p-5 border border-slate-800 shadow-xl relative overflow-hidden md:col-span-2 lg:col-span-1">
          <div className="absolute top-0 right-0 w-32 h-32 bg-blue-500/5 rounded-full blur-3xl -mr-10 -mt-10"></div>
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center gap-2 text-blue-400">
              <Database className="w-5 h-5" />
              <h2 className="font-semibold text-lg uppercase tracking-wider text-slate-300">Project Memory</h2>
            </div>
          </div>
          <div className="space-y-4">
            <div className="flex justify-between items-center border-b border-slate-800/50 pb-2">
              <span className="text-slate-500">Graph Size</span>
              <span className="font-mono font-medium text-slate-200">{metrics.memory.size}</span>
            </div>
            <div className="flex justify-between items-center border-b border-slate-800/50 pb-2">
              <span className="text-slate-500">Extracted Schemas</span>
              <span className="font-mono font-medium text-slate-300">{metrics.memory.schemas}</span>
            </div>
            <div className="flex justify-between items-center border-b border-slate-800/50 pb-2">
              <span className="text-slate-500">Active Relations</span>
              <span className="font-mono font-medium text-slate-300">{metrics.memory.relations}</span>
            </div>
            <div className="flex items-center gap-2 text-sm mt-4 text-slate-400">
              <Layers className="w-4 h-4" />
              <span>Index Status: </span>
              <span className="text-emerald-400 ml-auto flex items-center gap-1">
                <div className="w-2 h-2 rounded-full bg-emerald-500"></div> Up to date
              </span>
            </div>
          </div>
        </section>

        {/* Runtime Diagnostics Console */}
        <section className="bg-[#0c0f18] rounded-xl p-0 border border-slate-800 shadow-xl overflow-hidden md:col-span-2 lg:col-span-2 flex flex-col">
          <div className="bg-slate-900/80 px-4 py-3 border-b border-slate-800 flex items-center justify-between">
            <div className="flex items-center gap-2 text-slate-400">
              <Terminal className="w-4 h-4" />
              <h2 className="text-sm font-semibold uppercase tracking-wider">Controller Host Stream</h2>
            </div>
            <div className="flex gap-1">
              <div className="w-3 h-3 rounded-full bg-slate-700"></div>
              <div className="w-3 h-3 rounded-full bg-slate-700"></div>
              <div className="w-3 h-3 rounded-full bg-slate-700"></div>
            </div>
          </div>
          <div className="p-4 font-mono text-xs text-slate-400 flex-1 overflow-y-auto space-y-2">
            <div className="text-slate-500">[10:42:01.034] Booting OracleControllerHost v2.4.1</div>
            <div className="text-indigo-400">→ Starting runtime diagnostics aggregator connected on Port 9091</div>
            <div>[10:42:01.442] Resolved project root: <span className="text-blue-300">/Workspace/OracleOS</span></div>
            <div>[10:42:01.810] Loaded 843 policy constraints from cache.</div>
            <div className="text-amber-400">! Warning: System memory overhead exceeding target budget (4.2MB / 4.0MB)</div>
            <div className="text-emerald-400 mt-2">✨ Agent Loop Started. Waiting for IPC commands...</div>
            <div className="flex gap-2 items-center mt-4">
              <span className="text-slate-300">oracle-os &gt;</span>
              <span className="w-2 h-3 bg-slate-400 animate-pulse"></span>
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}

export default App;
