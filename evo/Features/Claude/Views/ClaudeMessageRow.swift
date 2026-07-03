//
//  ClaudeMessageRow.swift
//  evo
//
//  Renders a single `ClaudeChatManager.ChatMessage` in the side panel's
//  message list.
//

import SwiftUI

struct ClaudeMessageRow: View {
    let message: ClaudeChatManager.ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            switch message.role {
            case .user:
                Image(systemName: "person.crop.circle")
            case .assistant:
                Image(systemName: "sparkles")
            case .tool:
                Image(systemName: "wrench.and.screwdriver")
            }
            Text(message.role == .tool ? "▸ \(message.text)" : message.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(message.role == .tool ? .caption.monospaced() : .body)
        .padding(.vertical, 2)
    }
}
