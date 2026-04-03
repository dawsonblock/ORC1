import Foundation

// MCPDispatch+Memory.swift — Project memory tool implementations.
//
// Covers: oracle_memory_query, oracle_memory_draft

extension MCPDispatch {
    @MainActor
    static func dispatchMemory(
        _ request: MCPToolRequest,
        container: RuntimeContainer
    ) -> ToolResult {
        switch request.name {

        case "oracle_memory_query":
            guard let projectStore = container.memoryStore.projectStore else {
                return ToolResult(
                    success: false,
                    error: "Project memory not initialized. Ensure workspace root is set.",
                    suggestion: "The server needs a git workspace root to locate the ProjectMemory directory."
                )
            }
            let queryText = request.string("query") ?? ""
            let modules = request.strings("modules") ?? []
            let kindStrings = request.strings("kinds") ?? []
            let kinds = kindStrings.compactMap { ProjectMemoryKind(rawValue: $0) }
            let limit = request.int("limit") ?? 10
            let allRecords = projectStore.allRecords()
            let filtered: [ProjectMemoryRecord]
            if queryText.isEmpty && kinds.isEmpty && modules.isEmpty {
                filtered = Array(allRecords.prefix(limit))
            } else {
                filtered = Array(allRecords.filter { r in
                    let matchesQuery = queryText.isEmpty
                        || r.title.localizedCaseInsensitiveContains(queryText)
                        || r.summary.localizedCaseInsensitiveContains(queryText)
                        || r.body.localizedCaseInsensitiveContains(queryText)
                    let matchesKind = kinds.isEmpty || kinds.contains(r.kind)
                    let matchesModules = modules.isEmpty
                        || modules.contains { mod in r.affectedModules.contains(mod) }
                    return matchesQuery && matchesKind && matchesModules
                }.prefix(limit))
            }
            let serialized: [[String: Any]] = filtered.map { r in
                var d: [String: Any] = [
                    "id": r.id,
                    "kind": r.kind.rawValue,
                    "title": r.title,
                    "summary": r.summary,
                    "knowledge_class": r.knowledgeClass.rawValue,
                ]
                if !r.affectedModules.isEmpty { d["affected_modules"] = r.affectedModules }
                if !r.body.isEmpty { d["body"] = r.body }
                if !r.evidenceRefs.isEmpty { d["evidence_refs"] = r.evidenceRefs }
                return d
            }
            return ToolResult(success: true, data: ["records": serialized, "count": serialized.count])

        case "oracle_memory_draft":
            guard let title = request.string("title"),
                  let summary = request.string("summary"),
                  let kindStr = request.string("kind"),
                  let body = request.string("body") else {
                return ToolResult(
                    success: false,
                    error: "title, summary, kind, and body are all required for oracle_memory_draft"
                )
            }
            let validKinds = "architecture-decision, open-problem, rejected-approach, known-good-pattern, risk"
            guard ProjectMemoryKind(rawValue: kindStr) != nil else {
                return ToolResult(
                    success: false,
                    error: "Invalid kind '\(kindStr)'. Must be one of: \(validKinds)"
                )
            }
            let modules = request.strings("affected_modules") ?? []
            let refs = request.strings("evidence_refs") ?? []
            let memStore = container.memoryStore
            do {
                switch kindStr {
                case "architecture-decision":
                    try memStore.recordArchitectureDecision(
                        title: title, summary: summary, knowledgeClass: .reusable,
                        affectedModules: modules, evidenceRefs: refs, body: body
                    )
                case "open-problem":
                    try memStore.recordOpenProblem(
                        title: title, summary: summary, knowledgeClass: .reusable,
                        affectedModules: modules, evidenceRefs: refs, body: body
                    )
                case "rejected-approach":
                    try memStore.recordRejectedApproach(
                        title: title, summary: summary, knowledgeClass: .reusable,
                        affectedModules: modules, evidenceRefs: refs, body: body
                    )
                case "known-good-pattern":
                    try memStore.recordKnownGoodPattern(
                        title: title, summary: summary, knowledgeClass: .reusable,
                        affectedModules: modules, evidenceRefs: refs, body: body
                    )
                case "risk":
                    guard let ps = memStore.projectStore else {
                        return ToolResult(success: false, error: "Project memory not initialized")
                    }
                    _ = try ps.writeRiskDraft(
                        title: title, summary: summary, knowledgeClass: .reusable,
                        affectedModules: modules, evidenceRefs: refs, body: body
                    )
                default:
                    return ToolResult(success: false, error: "Unhandled kind: \(kindStr)")
                }
                return ToolResult(
                    success: true,
                    data: ["drafted": title, "kind": kindStr],
                    suggestion: "Memory record '\(title)' persisted. Retrieve with oracle_memory_query."
                )
            } catch {
                return ToolResult(success: false, error: "Failed to record memory: \(error)")
            }

        default:
            return ToolResult(success: false, error: "Unknown memory tool: \(request.name)")
        }
    }
}
