import SwiftUI

/// Decision rule for whether a Basic/Digest/NTLM auth challenge should be offered saved logins,
/// or should fall straight through to WebKit's own auth dialog (`.performDefaultHandling`).
enum BasicAuthPromptModel {
    /// Prompt only when we have candidate logins and the challenge hasn't already failed
    /// with our credentials (previousFailureCount > 0 → let WebKit show its own dialog).
    static func shouldPrompt(matchCount: Int, previousFailureCount: Int) -> Bool {
        matchCount > 0 && previousFailureCount == 0
    }
}

/// Minimal picker shown when a site issues an HTTP Basic/Digest/NTLM auth challenge and Evo has
/// one or more saved logins for that host. Presented from an `NSPanel` sheet — see
/// `TabBrowserPageDelegate.browserPage(_:didReceiveHTTPAuthChallengeForHost:completion:)`.
struct BasicAuthPromptView: View {
    let host: String
    let credentials: [ProviderCredential]
    let onSelect: (ProviderCredential?) -> Void

    @State private var selectedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in to \(host)")
                .font(.headline)
            Text("Choose a saved login to fill this site's sign-in prompt.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            List(credentials, selection: $selectedID) { credential in
                VStack(alignment: .leading, spacing: 2) {
                    Text(credential.title)
                        .font(.body)
                    Text(credential.displayUsername)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(credential.id)
            }
            .frame(minHeight: 120, maxHeight: 220)

            HStack {
                Spacer()
                Button("Cancel") {
                    onSelect(nil)
                }
                .keyboardShortcut(.cancelAction)

                Button("Fill") {
                    onSelect(credentials.first { $0.id == selectedID })
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedID == nil)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            if selectedID == nil {
                selectedID = credentials.first?.id
            }
        }
    }
}
