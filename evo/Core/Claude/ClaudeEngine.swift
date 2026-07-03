//
//  ClaudeEngine.swift
//  evo
//
//  Owns `claude` CLI binary resolution and MCP config wiring, then hands out
//  `ClaudeSession`s built from that resolved configuration: resolves the
//  binary path (`ClaudeBinaryLocator`), starts the in-process MCP server
//  (`EvoToolServer`), writes an mcp-config temp file pointing at its
//  endpoint, and constructs the session.
//

import Foundation

final class ClaudeEngine {
    static let shared = ClaudeEngine()

    private init() {}

    func makeSession(workingDirectory: URL) async throws -> ClaudeSession {
        let binary: String
        switch ClaudeBinaryLocator.resolve() {
        case let .success(p): binary = p
        case .failure:
            throw NSError(domain: "Evo.Claude", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "claude binary not found — set the path in Settings › Claude"
            ])
        }
        let endpoint = try await EvoToolServer.shared.start()
        let config: [String: Any] = ["mcpServers": ["evo": ["type": "http", "url": endpoint.absoluteString]]]
        let data = try JSONSerialization.data(withJSONObject: config)
        let path = NSTemporaryDirectory() + "evo-mcp-\(UUID().uuidString).json"
        try data.write(to: URL(fileURLWithPath: path))
        return ClaudeSession(binaryPath: binary, workingDirectory: workingDirectory, mcpConfigPath: path)
    }
}
