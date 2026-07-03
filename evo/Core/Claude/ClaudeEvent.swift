//
//  ClaudeEvent.swift
//  evo
//
//  Typed representation of the subset of `claude --output-format stream-json`
//  events the side panel needs. `ClaudeStreamEvent.parse(line:)` turns raw
//  stdout lines from the `claude` CLI into these cases.
//

/// A single decoded event from the `claude` CLI's `stream-json` output.
enum ClaudeEvent: Equatable {
    /// The CLI reported the session id it assigned (`type:"system"`, `subtype:"init"`).
    case sessionStarted(id: String)
    /// An assistant message contained a `text` content block.
    case assistantText(String)
    /// An assistant message contained a `tool_use` content block.
    case toolUse(name: String, id: String)
    /// A `user` message contained a `tool_result` content block.
    case toolResult(id: String, text: String, isError: Bool)
    /// The CLI reported the final `result` event, optionally with total cost in USD.
    case result(usageUSD: Double?)
    /// Parsing/execution failed in a way callers should surface.
    case failed(String)
}
