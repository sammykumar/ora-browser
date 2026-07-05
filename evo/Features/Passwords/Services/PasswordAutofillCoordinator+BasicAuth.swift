import Foundation

/// Support for HTTP Basic/Digest/NTLM auth-challenge prompting (Task 5.1). This is independent of
/// the JS bridge/in-page overlay — WKWebView calls into `BrowserPage`'s
/// `URLAuthenticationChallenge` handler before any page content (or the password-manager.js
/// bridge) exists. It reuses the same active-provider resolution the overlay uses so both
/// surfaces stay consistent with the user's chosen password manager.
extension PasswordAutofillCoordinator {
    /// Saved logins matching `host`, or `[]` if passwords are disabled, the tab is private, or the
    /// active provider has no matches. Callers should fall through to
    /// `.performDefaultHandling` when this returns empty.
    @MainActor
    func matchingCredentialsForHTTPAuth(host: String) async -> [ProviderCredential] {
        guard settings.passwordsEnabled,
              tab?.isPrivate == false,
              let url = URL(string: "https://\(host)/")
        else {
            return []
        }

        let provider = providers.activeProvider(for: settings.passwordManagerProvider)
        return await provider.credentials(for: url, containerID: tab?.container.id)
    }

    /// Reveals the secret for a credential chosen from the Basic-auth picker. Only called at the
    /// moment the user picks a credential — nothing is cached.
    @MainActor
    func revealForHTTPAuth(_ credential: ProviderCredential) async throws -> RevealedCredential {
        let provider = providers.activeProvider(for: settings.passwordManagerProvider)
        return try await provider.reveal(credential)
    }
}
