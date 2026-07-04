@testable import Evo
import Foundation
import Testing

struct OneTimeCodeFillTests {
    @Test func fillTotpSuggestionExposesStableID() {
        let cred = ProviderCredential(
            id: "acct:i1", ref: .onePassword(accountName: "acct", vaultID: "v", itemID: "i1"),
            title: "GitHub", username: "u", host: "github.com", accountLabel: "acct", hasTotp: true
        )
        let suggestion = PasswordAutofillSuggestion.fillOneTimeCode(cred)
        #expect(suggestion.id == "totp-acct:i1")
        #expect(suggestion.host == "github.com")
    }

    @Test func resolveSuggestionsSurfacesMatchedTotpCredentialAsFillOneTimeCode() {
        let matchedTotp = ProviderCredential(
            id: "acct:i1", ref: .onePassword(accountName: "acct", vaultID: "v", itemID: "i1"),
            title: "GitHub", username: "u", host: "github.com", accountLabel: "acct", hasTotp: true
        )
        let nonTotp = ProviderCredential(
            id: "acct:i2", ref: .onePassword(accountName: "acct", vaultID: "v", itemID: "i2"),
            title: "GitLab", username: "u2", host: "github.com", accountLabel: "acct", hasTotp: false
        )
        let focus = PasswordBridgeFocusPayload(
            fieldID: "otp-field", hostname: "github.com", action: .login, fieldKind: .oneTimeCode,
            usernameFieldID: nil, passwordFieldIDs: [],
            rect: PasswordBridgeRect(originX: 0, originY: 0, width: 1, height: 1)
        )

        let state = PasswordAutofillCoordinator.resolveSuggestions(
            for: focus,
            matchingEntries: [nonTotp, matchedTotp],
            emailSuggestions: [],
            generatedPassword: nil
        )

        #expect(state.suggestions.count == 1)
        #expect(state.suggestions.first?.id == "totp-acct:i1")
        if case let .fillOneTimeCode(credential) = state.suggestions.first {
            #expect(credential.id == "acct:i1")
        } else {
            Issue.record("Expected a fillOneTimeCode suggestion")
        }
    }
}
