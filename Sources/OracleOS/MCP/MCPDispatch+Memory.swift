import Foundation

// MCPDispatch+Memory.swift — Project memory tool implementations.
//
// Covers: oracle_memory_query, oracle_memory_draft

private struct MemoryRecordPayload: Encodable {
    let id: String
    let kind: String
    let title: String
    let summary: String
    let knowledgeClass: String
    let affectedModules: [String]?
    let body: String?
    let evidenceRefs: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case summary
        case knowledgeClass = "knowledge_class"
        case affectedModules = "affected_modules"
        case body
        case evidenceRefs = "evidence_refs"
    }
}

private struct MemoryQueryPayload: Encodable {
    let records: [MemoryRecordPayload]
    let count: Int
}

private struct MemoryDraftPayload: Encodable {
    let drafted: String
    let kind: String
}

extension MCPDispatch {
    @MainActor
    static func dispatchMemory(
        _ request: MCPToolRequest,
        container: RuntimeContainer
    ) -> ToolResult {
        switch request.name {

        case MCPToolName.memoryQuery:
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
            let payload = MemoryQueryPayload(
                records: filtered.map { record in
                    MemoryRecordPayload(
                        id: record.id,
                        kind: record.kind.rawValue,
                        title: record.title,
                        summary: record.summary,
                        knowledgeClass: record.knowledgeClass.rawValue,
                        affectedModules: record.affectedModules.isEmpty ? nil : record.affectedModules,
                        body: record.body.isEmpty ? nil : record.body,
                        evidenceRefs: record.evidenceRefs.isEmpty ? nil : record.evidenceRefs
                    )
                },
                count: filtered.count
            )
            guard let data = mcpLegacyJSONObject(from: payload) else {
                return ToolResult(success: false, error: "Failed to serialize memory query results")
            }
            return ToolResult(success: true, data: data)

        case MCPToolName.memoryDraft:
            guard let title = request.string("title"),
                  let summary = request.string("summary"),
                  let kindStr = request.string("kind"),
                  let body = request.string("body") else {
                return ToolResult(
                    success: false,
                    error: "title, summary, kind, and body are all required for \(MCPToolName.memoryDraft)"
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
                let payload = MemoryDraftPayload(drafted: title, kind: kindStr)
                guard let data = mcpLegacyJSONObject(from: payload) else {
                    return ToolResult(success: false, error: "Failed to serialize memory draft response")
                }
                return ToolResult(
                    success: true,
                    data: data,
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
