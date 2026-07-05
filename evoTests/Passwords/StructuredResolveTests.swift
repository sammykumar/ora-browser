@testable import Evo
import Foundation
import Testing

struct StructuredResolveTests {
    private func cardFocus() -> PasswordBridgeFocusPayload {
        PasswordBridgeFocusPayload(
            fieldID: "n", hostname: "shop.example.com", action: .login, fieldKind: .creditCard,
            usernameFieldID: nil, passwordFieldIDs: [],
            fields: [PasswordBridgeField(fieldID: "n", purpose: .cardNumber)],
            rect: PasswordBridgeRect(originX: 0, originY: 0, width: 1, height: 1)
        )
    }

    @Test func cardFocusSurfacesAllCardsNotHostFiltered() {
        let cards = [
            ProviderStructuredItem(
                id: "c1",
                ref: .onePassword(accountName: "a", vaultID: "v", itemID: "c1"),
                category: .creditCard,
                title: "Visa",
                subtitle: "Visa ····1234"
            ),
            ProviderStructuredItem(
                id: "c2",
                ref: .onePassword(accountName: "a", vaultID: "v", itemID: "c2"),
                category: .creditCard,
                title: "Amex",
                subtitle: "Amex ····9000"
            )
        ]
        let state = PasswordAutofillCoordinator.resolveSuggestions(
            for: cardFocus(), matchingEntries: [], emailSuggestions: [],
            generatedPassword: nil, structuredItems: cards
        )
        #expect(state.suggestions.map(\.id) == ["card-c1", "card-c2"])
    }
}
