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

    @Test func identityFocusSurfacesAllIdentities() {
        let ids = [ProviderStructuredItem(
            id: "i1",
            ref: .onePassword(accountName: "a", vaultID: "v", itemID: "i1"),
            category: .identity,
            title: "Home",
            subtitle: "Sam Kumar"
        )]
        let focus = PasswordBridgeFocusPayload(
            fieldID: "a", hostname: "shop.example.com", action: .login, fieldKind: .identity,
            usernameFieldID: nil, passwordFieldIDs: [],
            fields: [PasswordBridgeField(fieldID: "a", purpose: .addressLine1)],
            rect: PasswordBridgeRect(originX: 0, originY: 0, width: 1, height: 1)
        )
        let state = PasswordAutofillCoordinator.resolveSuggestions(
            for: focus, matchingEntries: [], emailSuggestions: [], generatedPassword: nil, structuredItems: ids
        )
        #expect(state.suggestions.map(\.id) == ["identity-i1"])
    }

    @Test func structuredFillEntriesSkipsMissingPurposes() async throws {
        let fields = [
            PasswordBridgeField(fieldID: "f1", purpose: .cardNumber),
            PasswordBridgeField(fieldID: "f2", purpose: .cvv),
            PasswordBridgeField(fieldID: "f3", purpose: .expDate)
        ]
        // Partial: the provider only has cardNumber and expDate for this item — cvv is absent.
        let provider = FakePasswordProvider(fillValuesResult: [.cardNumber: "4111111111111111", .expDate: "12/29"])
        let values = try await provider.fillValues(for: .onePassword(accountName: "a", vaultID: "v", itemID: "c1"))

        let entries = PasswordAutofillCoordinator.structuredFillEntries(fields: fields, values: values)

        #expect(entries.map(\.fieldID) == ["f1", "f3"])
        #expect(entries.map(\.value) == ["4111111111111111", "12/29"])
    }
}
