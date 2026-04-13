import Foundation

// MCPDispatch+Memory.swift — Project memory tool implementations.
//
// Covers: oracle_memory_query, oracle_memory_draft

struct MemoryRecordSummary: Encodable {
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

struct MemoryQueryPayload: Encodable {
    let records: [MemoryRecordSummary]
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
                    suggestion:
                        "The server needs a git workspace root to locate the ProjectMemory directory."
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
                filtered = Array(
                    allRecords.filter { record in
                        let matchesQuery =
                            queryText.isEmpty
                            || record.title.localizedCaseInsensitiveContains(queryText)
                            || record.summary.localizedCaseInsensitiveContains(queryText)
                            || record.body.localizedCaseInsensitiveContains(queryText)
                        let matchesKind = kinds.isEmpty || kinds.contains(record.kind)
                        let matchesModules =
                            modules.isEmpty
                            || modules.contains { module in record.affectedModules.contains(module)
                            }
                        return matchesQuery && matchesKind && matchesModules
                    }.prefix(limit))
            }
            let payload = MemoryQueryPayload(
                records: filtered.map { record in
                    MemoryRecordSummary(
                        id: record.id,
                        kind: record.kind.rawValue,
                        title: record.title,
                        summary: record.summary,
                        knowledgeClass: record.knowledgeClass.rawValue,
                        affectedModules: record.affectedModules.isEmpty
                            ? nil : record.affectedModules,
                        body: record.body.isEmpty ? nil : record.body,
                        evidenceRefs: record.evidenceRefs.isEmpty ? nil : record.evidenceRefs
                    )
                },
                count: filtered.count
            )
            return typedResult(payload)

        case MCPToolName.memoryDraft:
            guard let title = request.string("title"),
                let summary = request.string("summary"),
                let kindString = request.string("kind"),
                let body = request.string("body")
            else {
                return ToolResult(
                    success: false,
                    error:
                        "title, summary, kind, and body are all required for \(MCPToolName.memoryDraft)"
                )
            }
            let validKinds =
                "architecture-decision, open-problem, rejected-approach, known-good-pattern, risk"
            guard ProjectMemoryKind(rawValue: kindString) != nil else {
                return ToolResult(
                    success: false,
                    error: "Invalid kind '\(kindString)'. Must be one of: \(validKinds)"
                )
            }
            let modules = request.strings("affected_modules") ?? []
            let references = request.strings("evidence_refs") ?? []
            let memoryStore = container.memoryStore
            do {
                switch kindString {
                case "architecture-decision":
                    try memoryStore.recordArchitectureDecision(
                        title: title,
                        summary: summary,
                        knowledgeClass: .reusable,
                        affectedModules: modules,
                        evidenceRefs: references,
                        body: body
                    )
                case "open-problem":
                    try memoryStore.recordOpenProblem(
                        title: title,
                        summary: summary,
                        knowledgeClass: .reusable,
                        affectedModules: modules,
                        evidenceRefs: references,
                        body: body
                    )
                case "rejected-approach":
                    try memoryStore.recordRejectedApproach(
                        title: title,
                        summary: summary,
                        knowledgeClass: .reusable,
                        affectedModules: modules,
                        evidenceRefs: references,
                        body: body
                    )
                case "known-good-pattern":
                    try memoryStore.recordKnownGoodPattern(
                        title: title,
                        summary: summary,
                        knowledgeClass: .reusable,
                        affectedModules: modules,
                        evidenceRefs: references,
                        body: body
                    )
                case "risk":
                    guard let projectStore = memoryStore.projectStore else {
                        return ToolResult(success: false, error: "Project memory not initialized")
                    }
                    _ = try projectStore.writeRiskDraft(
                        title: title,
                        summary: summary,
                        knowledgeClass: .reusable,
                        affectedModules: modules,
                        evidenceRefs: references,
                        body: body
                    )
                default:
                    return ToolResult(success: false, error: "Unhandled kind: \(kindString)")
                }
                return typedResult(
                    MemoryDraftPayload(drafted: title, kind: kindString),
                    suggestion:
                        "Memory record '\(title)' persisted. Retrieve with oracle_memory_query."
                )
            } catch {
                return ToolResult(success: false, error: "Failed to record memory: \(error)")
            }

        default:
            return ToolResult(success: false, error: "Unknown memory tool: \(request.name)")
        }
    }
}
