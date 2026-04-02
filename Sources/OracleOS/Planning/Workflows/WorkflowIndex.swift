import Foundation

public final class WorkflowIndex: @unchecked Sendable {
    private var plans: [String: WorkflowPlan]
    private let decayPolicy: WorkflowDecayPolicy

    public init(
        plans: [String: WorkflowPlan] = [:],
        decayPolicy: WorkflowDecayPolicy = WorkflowDecayPolicy()
    ) {
        self.plans = plans
        self.decayPolicy = decayPolicy
        if !CommandLine.arguments.contains(where: { $0.contains("xctest") }) { loadFromDisk() }
    }

    private func loadFromDisk() {
        let dir = OracleProductPaths.workflowsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        for file in files where file.hasSuffix(".json") {
            let url = dir.appendingPathComponent(file)
            guard let data = try? Data(contentsOf: url),
                  let plan = try? decoder.decode(WorkflowPlan.self, from: data) else {
                continue
            }
            plans[plan.id] = plan
        }
    }

    private func saveToDisk(_ plan: WorkflowPlan) {
        let dir = OracleProductPaths.workflowsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let url = dir.appendingPathComponent("\(plan.id).json")
        if let data = try? encoder.encode(plan) {
            try? data.write(to: url)
        }
    }

    private func deleteFromDisk(id: String) {
        let dir = OracleProductPaths.workflowsDirectory
        let url = dir.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: url)
    }

    public func add(_ plan: WorkflowPlan) {
        plans[plan.id] = plan
        if !CommandLine.arguments.contains(where: { $0.contains("xctest") }) { saveToDisk(plan) }
    }

    public func plan(id: String) -> WorkflowPlan? {
        plans[id]
    }

    public func remove(id: String) {
        plans.removeValue(forKey: id)
        if !CommandLine.arguments.contains(where: { $0.contains("xctest") }) { deleteFromDisk(id: id) }
    }

    public func allPlans() -> [WorkflowPlan] {
        plans.values.sorted { lhs, rhs in
            if lhs.successRate == rhs.successRate {
                return lhs.goalPattern < rhs.goalPattern
            }
            return lhs.successRate > rhs.successRate
        }
    }

    public func promotedPlans(for agentKind: AgentKind? = nil) -> [WorkflowPlan] {
        allPlans().filter { plan in
            plan.promotionStatus == .promoted
                && !decayPolicy.isStale(plan)
                && (
                agentKind == nil
                                        || plan.agentKind == agentKind
            )
        }
    }

    /// Returns promoted workflows whose goal pattern matches the given goal.
    public func matching(goal: Goal) -> [WorkflowPlan] {
        let goalLower = goal.description.lowercased()
        return promotedPlans(for: goal.preferredAgentKind).filter { plan in
            let patternLower = plan.goalPattern.lowercased()
            return goalLower.contains(patternLower) || patternLower.contains(goalLower)
        }
    }
}
