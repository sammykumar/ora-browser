import AppKit
import SwiftUI

/// HTTP Basic/Digest/NTLM auth-challenge prompting (Task 5.1). This hooks WKWebView's
/// `URLAuthenticationChallenge` handler in `BrowserPage.swift` — it is independent of the JS
/// bridge/in-page overlay that drives normal form autofill.
extension TabBrowserPageDelegate {
    func browserPage(
        _ page: BrowserPage,
        didReceiveHTTPAuthChallengeForHost host: String,
        completion: @escaping (URLCredential?) -> Void
    ) {
        guard let passwordCoordinator else {
            completion(nil)
            return
        }

        Task { @MainActor [weak self] in
            let matches = await passwordCoordinator.matchingCredentialsForHTTPAuth(host: host)
            guard let self,
                  BasicAuthPromptModel.shouldPrompt(matchCount: matches.count, previousFailureCount: 0),
                  let window = page.window
            else {
                completion(nil)
                return
            }

            self.presentBasicAuthPrompt(host: host, credentials: matches, in: window) { chosen in
                guard let chosen else {
                    completion(nil)
                    return
                }

                Task { @MainActor in
                    guard let revealed = try? await passwordCoordinator.revealForHTTPAuth(chosen) else {
                        completion(nil)
                        return
                    }
                    completion(URLCredential(
                        user: revealed.username,
                        password: revealed.password,
                        persistence: .forSession
                    ))
                }
            }
        }
    }

    /// Presents `BasicAuthPromptView` as a sheet on the page's window and invokes `completion`
    /// exactly once — either with the chosen credential, or with `nil` on cancel/dismissal.
    @MainActor
    private func presentBasicAuthPrompt(
        host: String,
        credentials: [ProviderCredential],
        in window: NSWindow,
        completion: @escaping (ProviderCredential?) -> Void
    ) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false

        var didComplete = false
        let finish: (ProviderCredential?) -> Void = { credential in
            guard !didComplete else { return }
            didComplete = true
            completion(credential)
        }

        let promptView = BasicAuthPromptView(host: host, credentials: credentials) { chosen in
            window.endSheet(panel)
            finish(chosen)
        }
        let hostingView = NSHostingView(rootView: promptView)
        panel.contentView = hostingView
        panel.setContentSize(hostingView.fittingSize)

        window.beginSheet(panel) { _ in
            finish(nil)
        }
    }
}
