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
    @Published var draft: String = ""

    private let workingDirectory: URL
    private var session: ClaudeSession?
    private var pump: Task<Void, Never>?
    /// Creation guard: set synchronously (within one main-actor turn) BEFORE
    /// the `makeSession` await, so a second `send(_:)` arriving mid-creation
    /// can never observe `session == nil` and spawn a second subprocess.
    private var isCreatingSession = false
    /// Texts that arrived while the session was still being created.
    /// Chosen semantics: the user message is appended immediately
    /// (synchronous), the text is queued, and all queued texts are forwarded
    /// in arrival order once the one-and-only session lands. On creation
    /// failure the queue is dropped and the error surfaces as a ⚠️ chat row.
    private var pendingSends: [String] = []

    init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
    }

    func send(_ text: String) {
        messages.append(.init(role: .user, text: text))
        isRunning = true
        if let session {
            session.send(text)
            return
        }
        pendingSends.append(text)
        // Atomic check-then-set within this main-actor turn (no await above):
        // at most one creation Task is ever started.
        guard !isCreatingSession else { return }
        isCreatingSession = true
        Task {
            do {
                let newSession = try await ClaudeEngine.shared.makeSession(workingDirectory: workingDirectory)
                guard isCreatingSession else {
                    // shutdown() cleared isCreatingSession during the await; kill the fresh session instead.
                    newSession.terminate()
                    return
                }
                session = newSession
                pump = Task { [weak self] in
                    for await event in newSession.events {
                        self?.apply(event)
                    }
                }
                for pending in pendingSends {
                    newSession.send(pending)
                }
            } catch {
                apply(.failed(error.localizedDescription))
            }
            pendingSends.removeAll()
            isCreatingSession = false
        }
    }

    func stop() {
        session?.interrupt()
        // Drop anything queued during session creation so it doesn't forward
        // once the session lands after the user already hit Stop.
        pendingSends.removeAll()
        isRunning = false
    }

    /// Tears down the session, its subprocess, and the event-pump task.
    /// Idempotent — safe to call more than once (e.g. from both
    /// `.onDisappear` and an `NSWindow.willCloseNotification` observer).
    func shutdown() {
        pump?.cancel()
        pump = nil
        session?.terminate()
        session = nil
        pendingSends.removeAll()
        isCreatingSession = false
        isRunning = false
    }

    func apply(_ event: ClaudeEvent) {
        switch event {
        case .sessionStarted:
            break
        case let .assistantText(text):
            messages.append(.init(role: .assistant, text: text))
        case let .toolUse(name, _):
            let prefix = "mcp__evo__"
            let label = name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
            messages.append(.init(role: .tool, text: label))
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
