import Foundation

public struct MemoryDrafter: Sendable {
    private let llmClient: LLMClient
    
    public init(llmClient: LLMClient) {
        self.llmClient = llmClient
    }
    
    public func digestResidue(intent: String, summary: String, traceEvents: [TraceEvent]) async throws -> [ProjectMemoryDraft] {
        // We'll write the logic here to prompt the LLM
        return []
    }
}
