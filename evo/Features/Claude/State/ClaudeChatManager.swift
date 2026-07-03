//
//  ClaudeChatManager.swift
//  evo
//
//  Per-window owner of one `ClaudeSession`: consumes its `ClaudeEvent`
//  stream and reduces it into `@Published` chat state the side panel
//  (Task 8) renders. `apply(_:)` is a pure reducer kept separate from the
//  session-spawning `send(_:)` so it can be unit tested without spawning a
//  real `claude` subprocess.
//

import Foundation

@MainActor final class ClaudeChatManager: ObservableObject {
    struct ChatMessage: Identifiable, Equatable {
        enum Role {
            case user
            case assistant
            case tool
        }

        let id = UUID()
        var role: Role
        var text: String
    }

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isRunning = false

    private let workingDirectory: URL
    private var session: ClaudeSession?
    private var pump: Task<Void, Never>?

    init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
    }

    func send(_ text: String) {
        messages.append(.init(role: .user, text: text))
        isRunning = true
        Task {
            do {
                if session == nil {
                    let newSession = try await ClaudeEngine.shared.makeSession(workingDirectory: workingDirectory)
                    session = newSession
                    pump = Task { [weak self] in
                        for await event in newSession.events {
                            self?.apply(event)
                        }
                    }
                }
                session?.send(text)
            } catch {
                apply(.failed(error.localizedDescription))
            }
        }
    }

    func stop() {
        session?.interrupt()
        isRunning = false
    }

    func apply(_ event: ClaudeEvent) {
        switch event {
        case .sessionStarted:
            break
        case let .assistantText(text):
            messages.append(.init(role: .assistant, text: text))
        case let .toolUse(name, _):
            messages.append(.init(role: .tool, text: name.replacingOccurrences(of: "mcp__evo__", with: "")))
        case .toolResult:
            break
        case .result:
            isRunning = false
        case let .failed(message):
            messages.append(.init(role: .assistant, text: "⚠️ \(message)"))
            isRunning = false
        }
    }

    func setRunningForTesting(_ value: Bool) {
        isRunning = value
    }
}
