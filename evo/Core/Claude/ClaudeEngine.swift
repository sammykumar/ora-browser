//
//  ClaudeEngine.swift
//  evo
//
//  Owns `claude` CLI binary resolution and MCP config wiring, then hands out
//  `ClaudeSession`s built from that resolved configuration. Resolution
//  itself (binary lookup: Task 4; mcp-config generation: Task 6) is not yet
//  implemented — this is the session-owning shell those tasks fill in.
//

import Foundation

final class ClaudeEngine {
    static let shared = ClaudeEngine()

    private init() {}

    // makeSession(workingDirectory:) is completed in Task 6 (binary + mcp-config).
}
