@testable import Evo
import Foundation
import Testing

struct ClaudeStreamEventTests {
    @Test func parsesSessionInit() {
        let line = #"{"type":"system","subtype":"init","session_id":"abc-123"}"#
        #expect(ClaudeStreamEvent.parse(line: line) == .sessionStarted(id: "abc-123"))
    }

    @Test func parsesAssistantText() {
        let line = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hello"}]}}"#
        #expect(ClaudeStreamEvent.parse(line: line) == .assistantText("Hello"))
    }

    @Test func parsesToolUse() {
        let line = """
        {"type":"assistant","message":{"content":[\
        {"type":"tool_use","id":"tu_1","name":"mcp__evo__read_current_page","input":{}}]}}
        """
        #expect(ClaudeStreamEvent.parse(line: line) == .toolUse(name: "mcp__evo__read_current_page", id: "tu_1"))
    }

    @Test func parsesResultWithCost() {
        let line = #"{"type":"result","subtype":"success","total_cost_usd":0.0123}"#
        #expect(ClaudeStreamEvent.parse(line: line) == .result(usageUSD: 0.0123))
    }

    @Test func ignoresBlankAndGarbage() {
        #expect(ClaudeStreamEvent.parse(line: "") == nil)
        #expect(ClaudeStreamEvent.parse(line: "not json") == nil)
        #expect(ClaudeStreamEvent.parse(line: #"{"type":"unknown_kind"}"#) == nil)
    }

    /// End-to-end pin against a real captured `claude` CLI transcript (see
    /// `Fixtures/hello.jsonl`, captured by running the exact command from the
    /// task brief). This guards against the hand-written literals above
    /// drifting from what the real CLI actually emits.
    ///
    /// Located relative to this source file (rather than as a bundled
    /// resource) so the test doesn't depend on `.jsonl` being wired into the
    /// test target's Copy Bundle Resources phase.
    @Test func parsesCapturedFixtureEndToEnd() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/hello.jsonl")
        let contents = try String(contentsOf: fixtureURL, encoding: .utf8)
        let events = contents.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { ClaudeStreamEvent.parse(line: String($0)) }

        #expect(events.contains { if case .sessionStarted = $0 { return true } else { return false } })
        #expect(events.contains { if case .assistantText = $0 { return true } else { return false } })
        #expect(events.contains { if case .result = $0 { return true } else { return false } })
    }
}
