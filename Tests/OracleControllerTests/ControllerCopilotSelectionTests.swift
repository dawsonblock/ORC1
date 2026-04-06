import Foundation
import Testing
@testable import OracleControllerHost
@testable import OracleControllerShared

struct ControllerCopilotSelectionTests {
    @Test
    func prefersOpenAIProviderWhenExplicitHintsExist() {
        let selected = ControllerCopilot.selectStatus(
            openAIStatus: makeStatus(
                providerID: "openai-compatible",
                displayName: "DeepSeek",
                state: .setupRequired,
                configured: false,
                available: false
            ),
            claudeStatus: makeStatus(
                providerID: "claude-local",
                displayName: "Claude Local",
                state: .ready,
                configured: true,
                available: true,
                canStream: true
            ),
            hasExplicitOpenAIHints: true
        )

        #expect(selected.providerID == "openai-compatible")
        #expect(selected.displayName == "DeepSeek")
        #expect(selected.state == .setupRequired)
    }

    @Test
    func fallsBackToClaudeWhenNoOpenAIHintsExist() {
        let claudeStatus = makeStatus(
            providerID: "claude-local",
            displayName: "Claude Local",
            state: .ready,
            configured: true,
            available: true,
            canStream: true
        )
        let selected = ControllerCopilot.selectStatus(
            openAIStatus: makeStatus(
                providerID: "openai-compatible",
                displayName: "DeepSeek",
                state: .setupRequired,
                configured: false,
                available: false
            ),
            claudeStatus: claudeStatus,
            hasExplicitOpenAIHints: false
        )

        #expect(selected == claudeStatus)
    }

    @Test
    func returnsGenericFallbackWhenNeitherProviderIsUsable() {
        let selected = ControllerCopilot.selectStatus(
            openAIStatus: makeStatus(
                providerID: "openai-compatible",
                displayName: "OpenAI Compatible",
                state: .setupRequired,
                configured: false,
                available: false
            ),
            claudeStatus: makeStatus(
                providerID: "claude-local",
                displayName: "Claude Local",
                state: .setupRequired,
                configured: false,
                available: false,
                canStream: true
            ),
            hasExplicitOpenAIHints: false
        )

        #expect(selected.providerID == "copilot-unconfigured")
        #expect(selected.state == .setupRequired)
        #expect(selected.available == false)
    }

    @Test
    func detectsAnyExplicitOpenAIHint() {
        #expect(ControllerCopilot.hasExplicitOpenAIHints(in: ["ORACLE_LLM_API_KEY": "token"]))
        #expect(ControllerCopilot.hasExplicitOpenAIHints(in: ["ORACLE_LLM_BASE_URL": "https://api.deepseek.com"]))
        #expect(ControllerCopilot.hasExplicitOpenAIHints(in: ["ORACLE_LLM_MODEL": "deepseek-chat"]))
        #expect(!ControllerCopilot.hasExplicitOpenAIHints(in: [:]))
        #expect(!ControllerCopilot.hasExplicitOpenAIHints(in: ["ORACLE_LLM_API_KEY": ""]))
    }

    private func makeStatus(
        providerID: String,
        displayName: String,
        state: ChatProviderState,
        configured: Bool,
        available: Bool,
        canStream: Bool = false
    ) -> ChatProviderStatus {
        ChatProviderStatus(
            providerID: providerID,
            displayName: displayName,
            state: state,
            configured: configured,
            available: available,
            canStream: canStream,
            detail: "test"
        )
    }
}