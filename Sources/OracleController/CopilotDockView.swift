import AppKit
import SwiftUI
import OracleControllerShared

struct CopilotDockView<Inspector: View>: View {
    @Bindable var store: ControllerStore
    @Environment(ControllerLayoutSettings.self) private var layout
    @ViewBuilder let inspector: Inspector

    @FocusState private var isInputFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: layout.stackSpacing) {
                    PanelCard("AI Copilot", subtitle: store.chatProviderStatus?.detail ?? "Local advisory assistant for runtime state", style: .hero) {
                    HStack(spacing: 8) {
                        StatusBadge(
                            label: store.chatProviderStatus?.displayName ?? "Copilot",
                            tone: providerTone
                        )
                        if let state = store.chatProviderStatus?.state {
                            StatusBadge(
                                label: state.rawValue.replacingOccurrences(of: "_", with: " ").capitalized,
                                tone: providerTone
                            )
                        }

                        Spacer()

                        Button {
                            store.clearChatConversation()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ControllerTheme.muted)
                                .padding(6)
                                .background(ControllerTheme.panelRaised, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Clear chat history")
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        MetricTile(
                            label: "Provider",
                            value: store.chatProviderStatus?.displayName ?? "Copilot",
                            detail: store.chatProviderStatus?.detail ?? "No provider details yet",
                            tone: providerTone
                        )
                        MetricTile(
                            label: "Conversation",
                            value: "\(store.chatConversation?.messages.count ?? 0)",
                            detail: store.isChatStreaming ? "Streaming a response" : "Ready for a prompt",
                            tone: store.isChatStreaming ? .warning : .good
                        )
                    }

                    ChipRow(values: store.copilotContextChips)

                    if let messages = store.chatConversation?.messages, !messages.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(messages) { message in
                                ChatMessageBubble(message: message, store: store)
                                    .id(message.id)
                            }
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: messages.count)
                    } else {
                        EmptyStateView(
                            systemImage: "message.badge.waveform",
                            title: "Copilot is ready for context",
                            message: "Ask for runtime triage, approval summaries, trace interpretation, or the safest next step."
                        )
                        .frame(height: 220)
                    }

                    if let prompts = store.missionControl?.recommendedPrompts, !prompts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggested prompts")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            ChipRow(values: prompts) { prompt in
                                store.chatInput = prompt
                                Task { await store.sendChatMessage() }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .bottom, spacing: 8) {
                            TextField("Ask the controller copilot", text: $store.chatInput, axis: .vertical)
                                .textFieldStyle(.plain)
                                .lineLimit(1...8)
                                .font(.system(size: 14))
                                .padding(12)
                                .background(ControllerTheme.panelRaised, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(ControllerTheme.borderStrong.opacity(0.4), lineWidth: 1)
                                )
                                .focused($isInputFocused)
                                .onSubmit {
                                    Task { 
                                        await store.sendChatMessage() 
                                        isInputFocused = true
                                    }
                                }

                            if store.isChatStreaming {
                                Button {
                                    Task { 
                                        await store.cancelChatMessage()
                                        isInputFocused = true
                                    }
                                } label: {
                                    Image(systemName: "stop.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(.white, ControllerTheme.warning)
                                }
                                .buttonStyle(.plain)
                                .padding(.bottom, 6)
                            } else {
                                Button {
                                    Task { 
                                        await store.sendChatMessage() 
                                        isInputFocused = true
                                    }
                                } label: {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(store.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ControllerTheme.muted : .white, store.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ControllerTheme.borderStrong : ControllerTheme.accent)
                                }
                                .buttonStyle(.plain)
                                .disabled(store.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .padding(.bottom, 6)
                            }
                        }
                    }
                }

                PanelCard("Inspector", subtitle: store.selectedSection.title, style: .muted) {
                    inspector
                }
            }
            .padding(max(12, layout.workspacePaddingValue - 4))
            .onChange(of: store.chatConversation?.messages.last?.id) { _, newID in
                if let newID = newID {
                    withAnimation {
                        proxy.scrollTo(newID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: store.chatConversation?.updatedAt) { _, _ in
                if let lastID = store.chatConversation?.messages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                isInputFocused = true
            }
        }
        }
        .frame(minWidth: max(420, layout.inspectorColumnWidth * 0.88))
    }

    private var providerTone: StatusBadge.Tone {
        guard let state = store.chatProviderStatus?.state else {
            return .neutral
        }
        switch state {
        case .ready:
            return .good
        case .unavailable:
            return .warning
        case .setupRequired:
            return .neutral
        }
    }
}

private struct ChipRow: View {
    let values: [String]
    var action: ((String) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button {
                        action?(value)
                    } label: {
                        Text(value)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(ControllerTheme.ink)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(ControllerTheme.panelRaised.opacity(0.92), in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(ControllerTheme.borderStrong.opacity(0.65), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(action == nil)
                }
            }
        }
    }
}

private struct ChatMessageBubble: View {
    let message: ChatMessage
    @Bindable var store: ControllerStore
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: message.role == .user ? "person.crop.circle.fill" : "sparkles")
                    .foregroundStyle(roleTone.color)
                    .font(.system(size: 14))

                Text(message.role.rawValue.capitalized)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(ControllerTheme.ink)

                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ControllerTheme.muted)
            }

            Group {
                if message.content.isEmpty && message.isStreaming {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.8)
                        Text("Thinking…")
                            .foregroundStyle(ControllerTheme.muted)
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .padding(12)
                    .background(bubbleColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(roleTone.color.opacity(0.14), lineWidth: 1)
                    )
                } else {
                    Text(
                        (try? AttributedString(
                            markdown: message.content,
                            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                        )) ?? AttributedString(message.content)
                    )
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .padding(12)
                        .background(bubbleColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(roleTone.color.opacity(0.14), lineWidth: 1)
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant && !message.content.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.content, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.clipboard")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(ControllerTheme.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(ControllerTheme.panelRaised, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(ControllerTheme.borderStrong, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
            }

            if !message.citations.isEmpty {
                ChipRow(values: message.citations.map(\.title)) { title in
                    guard let citation = message.citations.first(where: { $0.title == title }) else { return }
                    store.openCitation(citation)
                }
            }

            if !message.draftActions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(message.draftActions) { draft in
                        Button {
                            Task { await store.applyDraft(draft) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.title)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(draft.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(ControllerTheme.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(ControllerTheme.panelRaised.opacity(0.94), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .onHover { hovering in
            isHovered = hovering
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var bubbleColor: Color {
        switch message.role {
        case .system:
            return ControllerTheme.panel.opacity(0.88)
        case .user:
            return ControllerTheme.accent.opacity(0.12)
        case .assistant:
            return ControllerTheme.panelRaised.opacity(0.94)
        }
    }

    private var roleTone: StatusBadge.Tone {
        switch message.role {
        case .system:
            return .neutral
        case .user:
            return .good
        case .assistant:
            return .warning
        }
    }
}
