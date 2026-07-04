@testable import Evo
import Foundation
import Testing

struct OverlaySuggestionTests {
    private func cred(_ id: String, host: String) -> ProviderCredential {
        ProviderCredential(
            id: id, ref: .onePassword(accountName: "acct", vaultID: "v", itemID: id),
            title: host, username: "sam", host: host, accountLabel: "acct", hasTotp: false
        )
    }

    @Test func savedCredentialSuggestionExposesHostAndID() {
        let suggestion = PasswordAutofillSuggestion.savedCredential(cred("i1", host: "example.com"))
        #expect(suggestion.host == "example.com")
        #expect(suggestion.id == "saved-i1")
    }

    @Test func stateOrdersGeneratedThenSaved() {
        let focus = PasswordBridgeFocusPayload(
            fieldID: "f", hostname: "example.com", action: .login, fieldKind: .password,
            usernameFieldID: nil, passwordFieldIDs: ["p"],
            rect: PasswordBridgeRect(originX: 0, originY: 0, width: 1, height: 1)
        )
        let state = PasswordAutofillOverlayState(
            focus: focus, savedPasswordEntries: [cred("i1", host: "example.com")],
            emailSuggestions: [], generatedPassword: nil, selectedSuggestionIndex: 0
        )
        #expect(state.suggestions.count == 1)
        #expect(state.suggestions.first?.id == "saved-i1")
    }
}
