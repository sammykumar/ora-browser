//
//  ClaudeChatManagerTests.swift
//  evoTests
//
//  Exercises only the `apply(_:)` reducer — no `send()` calls here, since
//  that would spawn a real `claude` subprocess via `ClaudeEngine.shared`.
//

@testable import Evo
import Foundation
import Testing

@MainActor struct ClaudeChatManagerTests {
    @Test func appendsAssistantText() {
        let manager = ClaudeChatManager(workingDirectory: URL(fileURLWithPath: NSHomeDirectory()))
        manager.apply(.assistantText("Hi"))
        #expect(manager.messages.last?.role == .assistant)
        #expect(manager.messages.last?.text == "Hi")
    }

    @Test func toolUseAppearsAsToolRow() {
        let manager = ClaudeChatManager(workingDirectory: URL(fileURLWithPath: NSHomeDirectory()))
        manager.apply(.toolUse(name: "mcp__evo__read_current_page", id: "t1"))
        #expect(manager.messages.last?.role == .tool)
        #expect(manager.messages.last?.text.contains("read_current_page") == true)
    }

    @Test func resultClearsRunning() {
        let manager = ClaudeChatManager(workingDirectory: URL(fileURLWithPath: NSHomeDirectory()))
        manager.setRunningForTesting(true)
        manager.apply(.result(usageUSD: 0.01))
        #expect(manager.isRunning == false)
    }
}
