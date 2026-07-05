@testable import Evo
import Foundation
import Testing

struct OneTimeCodeDecodeTests {
    @Test func decodesOneTimeCodeFocus() throws {
        let json = """
        {"type":"focus","focus":{"fieldID":"f","hostname":"example.com","action":"login",
        "fieldKind":"oneTimeCode","usernameFieldID":null,"passwordFieldIDs":[],
        "rect":{"x":0,"y":0,"width":1,"height":1}}}
        """
        let event = try JSONDecoder().decode(PasswordBridgeEvent.self, from: Data(json.utf8))
        #expect(event.focus?.fieldKind == .oneTimeCode)
    }

    @Test func resolveSuggestionsFiltersToTotpCredentialsForOneTimeCodeFocus() {
        let focus = PasswordBridgeFocusPayload(
            fieldID: "f", hostname: "example.com", action: .login, fieldKind: .oneTimeCode,
            usernameFieldID: nil, passwordFieldIDs: [],
            rect: PasswordBridgeRect(originX: 0, originY: 0, width: 1, height: 1)
        )
        let withTotp = ProviderCredential(
            id: "i1", ref: .onePassword(accountName: "acct", vaultID: "v", itemID: "i1"),
            title: "example.com", username: "sam", host: "example.com", accountLabel: "acct", hasTotp: true
        )
        let withoutTotp = ProviderCredential(
            id: "i2", ref: .onePassword(accountName: "acct", vaultID: "v", itemID: "i2"),
            title: "example.com", username: "sam2", host: "example.com", accountLabel: "acct", hasTotp: false
        )

        let state = PasswordAutofillCoordinator.resolveSuggestions(
            for: focus,
            matchingEntries: [withTotp, withoutTotp],
            emailSuggestions: [],
            generatedPassword: nil
        )

        // A one-time-code focus surfaces the matched TOTP-bearing credential as a
        // dedicated "fill one-time code" row (not an ordinary saved-credential row),
        // and the non-TOTP credential is excluded.
        #expect(state.oneTimeCodeCredential?.id == "i1")
        #expect(state.savedPasswordEntries.isEmpty)
        #expect(state.suggestions.map(\.id) == ["totp-i1"])
    }
}
