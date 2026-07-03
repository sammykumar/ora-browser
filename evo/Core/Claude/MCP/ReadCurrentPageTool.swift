//
//  ReadCurrentPageTool.swift
//  Evo
//
//  Pure handler for the `read_current_page` MCP tool: given an
//  `ActiveTabTextProvider` (or `nil`, when no window has registered one),
//  produces the text/isError tuple the MCP `CallTool` response is built from.
//  Kept free of the MCP SDK and `EvoToolServer`'s transport plumbing so it can
//  be unit-tested with a stub provider.
//

import Foundation

enum ReadCurrentPageTool {
    static func run(provider: ActiveTabTextProvider?) async -> (text: String, isError: Bool) {
        guard let provider else { return ("no active tab available", true) }
        switch await provider.currentPageText() {
        case let .success(text): return (text, false)
        case .failure(.noActiveTab): return ("no active tab available", true)
        case let .failure(.evalFailed(m)): return ("failed to read page: \(m)", true)
        }
    }
}
