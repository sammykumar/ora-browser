//
//  ClaudeStreamEvent.swift
//  evo
//
//  Parses one line of `claude --output-format stream-json` stdout into a
//  `ClaudeEvent`. Never throws: malformed, blank, or unrecognized lines
//  return `nil` so a caller reading a subprocess pipe line-by-line can just
//  skip them.
//
//  Key names below were verified against real captured fixtures (see
//  `evoTests/Claude/Fixtures/hello.jsonl` and `Fixtures/tool-use.jsonl`)
//  rather than assumed. One reality discovered there: environments with
//  SessionStart hooks configured produce `type:"system"` lines (subtypes
//  `hook_started` / `hook_response`) that also carry `session_id`, alongside
//  the real `subtype:"init"` line that carries the session id. Only
//  `subtype:"init"` is treated as the session-start event so those
//  hook-noise lines don't spuriously double-fire `.sessionStarted`.
//

import Foundation

enum ClaudeStreamEvent {
    /// Parses a single `stream-json` line into a `ClaudeEvent`, or `nil` if the
    /// line is blank, not valid JSON, or not one of the recognized event shapes.
    static func parse(line: String) -> ClaudeEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else {
            return nil
        }

        switch type {
        case "system":
            return parseSystem(obj)
        case "assistant":
            return parseAssistant(obj)
        case "result":
            return .result(usageUSD: obj["total_cost_usd"] as? Double)
        default:
            return nil
        }
    }

    private static func parseSystem(_ obj: [String: Any]) -> ClaudeEvent? {
        guard obj["subtype"] as? String == "init", let id = obj["session_id"] as? String else {
            return nil
        }
        return .sessionStarted(id: id)
    }

    private static func parseAssistant(_ obj: [String: Any]) -> ClaudeEvent? {
        guard let message = obj["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]]
        else {
            return nil
        }

        for part in content {
            switch part["type"] as? String {
            case "text":
                if let text = part["text"] as? String { return .assistantText(text) }
            case "tool_use":
                if let name = part["name"] as? String, let id = part["id"] as? String {
                    return .toolUse(name: name, id: id)
                }
            default:
                continue
            }
        }
        return nil
    }
}
