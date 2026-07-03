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

    /// Regression test for the `subtype == "init"` guard in `parseSystem`:
    /// SessionStart hook lines also carry `type:"system"` and `session_id`,
    /// but must NOT be treated as `.sessionStarted`. Literal copied verbatim
    /// from a real captured hook line in `Fixtures/hello.jsonl`.
    @Test func ignoresHookStartedSystemLineDespiteSessionId() {
        // swiftlint:disable:next line_length
        let line = #"{"type":"system","subtype":"hook_started","hook_id":"0371af0b-d07e-4248-b542-43f1ddbec439","hook_name":"SessionStart:startup","hook_event":"SessionStart","uuid":"2aecc71c-e2a5-4c53-b009-44cfcdf22a47","session_id":"d8b0ad28-f061-44bb-b5c3-a4ab3a10dfbd"}"#
        #expect(ClaudeStreamEvent.parse(line: line) == nil)
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
        let events = try parseFixture(named: "hello.jsonl")

        let sessionStartedCount = events.filter { if case .sessionStarted = $0 { return true } else { return false } }
            .count
        #expect(sessionStartedCount == 1)
        #expect(events.contains { if case .assistantText = $0 { return true } else { return false } })
        #expect(events.contains { if case .result = $0 { return true } else { return false } })
    }

    /// End-to-end pin against a real captured `claude` CLI transcript that
    /// contains a genuine `tool_use` content block (see
    /// `Fixtures/tool-use.jsonl`, captured by running a Bash-tool-using
    /// prompt through the `claude` CLI per the task brief). Confirms the
    /// `name`/`id` key extraction in `parseAssistant`'s `tool_use` branch
    /// matches real CLI output rather than an untested hypothesis.
    @Test func parsesCapturedToolUseFixtureEndToEnd() throws {
        let events = try parseFixture(named: "tool-use.jsonl")

        let toolUseEvents = events.compactMap { event -> (name: String, id: String)? in
            if case let .toolUse(name, id) = event { return (name, id) }
            return nil
        }
        #expect(!toolUseEvents.isEmpty)
        #expect(toolUseEvents.contains { $0.name == "Bash" && !$0.id.isEmpty })
    }

    private func parseFixture(named name: String) throws -> [ClaudeEvent] {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        let contents = try String(contentsOf: fixtureURL, encoding: .utf8)
        return contents.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { ClaudeStreamEvent.parse(line: String($0)) }
    }
}
