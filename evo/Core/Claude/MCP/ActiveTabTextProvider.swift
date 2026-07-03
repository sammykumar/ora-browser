//
//  ActiveTabTextProvider.swift
//  Evo
//
//  Bridges the per-window `TabManager` to an app-wide MCP server. `TabManager`
//  is constructed once per `EvoRoot` (one per browser window), so there is no
//  single app-wide "active tab." `FrontmostTabRegistry` holds a weak reference
//  to whichever window's provider last registered itself as frontmost, giving
//  Task 6's `read_current_page` MCP tool a single app-wide seam to call through.
//
//  NOTE: The `Evo` module declares a module-level `struct Result` (see
//  evo/Features/Importer/Services/Importer.swift), which shadows the stdlib
//  `Result` enum. The signature below must spell out `Swift.Result` to bind to
//  the standard library type instead of the shadowing struct.
//

import Foundation

enum PageReadError: Error, Equatable {
    case noActiveTab
    case evalFailed(String)
}

protocol ActiveTabTextProvider: AnyObject {
    func currentPageText() async -> Swift.Result<String, PageReadError>
}

/// App-wide, `@MainActor` registry of the frontmost window's `ActiveTabTextProvider`.
/// Holds the provider weakly — the owning window (`EvoRoot`) is responsible for
/// keeping a strong reference alive for as long as it wants to remain registerable.
@MainActor
final class FrontmostTabRegistry {
    static let shared = FrontmostTabRegistry()

    private init() {}

    private(set) weak var provider: ActiveTabTextProvider?

    func setFrontmost(_ provider: ActiveTabTextProvider?) {
        self.provider = provider
    }
}

/// Reads the active tab's visible text by evaluating `document.body.innerText`
/// in that tab's `WKWebView`.
@MainActor
final class LiveActiveTabTextProvider: ActiveTabTextProvider {
    private let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    func currentPageText() async -> Swift.Result<String, PageReadError> {
        guard let tab = tabManager.activeTab else { return .failure(.noActiveTab) }
        // Unhydrated tab's evaluateJavaScript silently no-ops; ensure tab is ready before continuing.
        guard tab.browserPage != nil else { return .failure(.noActiveTab) }
        return await withCheckedContinuation { continuation in
            tab.evaluateJavaScript("document.body.innerText") { value, error in
                if let error {
                    continuation.resume(returning: .failure(.evalFailed(error.localizedDescription)))
                } else {
                    continuation.resume(returning: .success((value as? String) ?? ""))
                }
            }
        }
    }
}
