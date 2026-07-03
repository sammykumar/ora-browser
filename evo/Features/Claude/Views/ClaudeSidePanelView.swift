//
//  ClaudeSidePanelView.swift
//  evo
//
//  Message list + composer for the Claude side panel (Task 8). Docked as
//  the secondary pane of a nested `HSplit` in `BrowserSplitView`.
//

import SwiftUI

struct ClaudeSidePanelView: View {
    @ObservedObject var chat: ClaudeChatManager

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(chat.messages) { ClaudeMessageRow(message: $0).id($0.id) }
                    }
                    .padding(12)
                }
                .onChange(of: chat.messages.count) { _, _ in
                    if let last = chat.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("Ask Claude about this page…", text: $chat.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .onSubmit(submit)
                Button(action: chat.isRunning ? chat.stop : submit) {
                    Image(systemName: chat.isRunning ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(chat.draft.isEmpty && !chat.isRunning)
            }
            .padding(12)
        }
        .frame(minWidth: 280)
        .background(.regularMaterial)
    }

    private func submit() {
        // Defense-in-depth: never send while a turn is already running — the
        // manager itself guards double session-creation, but a second send
        // mid-run would still interleave turns within one session.
        guard !chat.isRunning else { return }
        let text = chat.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chat.send(text)
        chat.draft = ""
    }
}
