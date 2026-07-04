@testable import Evo
import Foundation
import Testing

@MainActor
struct SaveRoutingTests {
    @Test func buildsOnePasswordSaveTargetForSingleAccount() {
        let target = PasswordAutofillCoordinator.saveTarget(
            forProvider: .onePassword, accounts: ["acct"], defaultVaultID: "v1",
            containerID: nil, existingItemID: nil
        )
        guard case let .onePassword(accountName, vaultID, existing) = target else {
            Issue.record("expected onePassword target")
            return
        }
        #expect(accountName == "acct")
        #expect(vaultID == "v1")
        #expect(existing == nil)
    }

    @Test func evoProviderBuildsContainerTarget() {
        let id = UUID()
        let target = PasswordAutofillCoordinator.saveTarget(
            forProvider: .evo, accounts: [], defaultVaultID: nil, containerID: id, existingItemID: nil
        )
        guard case let .evoContainer(containerID) = target else {
            Issue.record("expected evoContainer target")
            return
        }
        #expect(containerID == id)
    }

    @Test func existingOnePasswordItemIDReturnsRefWhenUsernameMatches() {
        let credentials = [
            makeOnePasswordCredential(username: "someone-else", accountName: "acct", vaultID: "v1", itemID: "item-1"),
            makeOnePasswordCredential(username: "sam@example.com", accountName: "acct", vaultID: "v2", itemID: "item-2")
        ]

        let match = PasswordAutofillCoordinator.existingOnePasswordItemID(
            matching: "sam@example.com",
            in: credentials
        )

        #expect(match?.accountName == "acct")
        #expect(match?.vaultID == "v2")
        #expect(match?.itemID == "item-2")
    }

    @Test func existingOnePasswordItemIDReturnsNilWhenNoUsernameMatches() {
        let credentials = [
            makeOnePasswordCredential(username: "someone-else", accountName: "acct", vaultID: "v1", itemID: "item-1")
        ]

        let match = PasswordAutofillCoordinator.existingOnePasswordItemID(
            matching: "sam@example.com",
            in: credentials
        )

        #expect(match == nil)
    }

    @Test func existingOnePasswordItemIDReturnsNilForEmptyCredentials() {
        let match = PasswordAutofillCoordinator.existingOnePasswordItemID(matching: "sam@example.com", in: [])
        #expect(match == nil)
    }

    private func makeOnePasswordCredential(
        username: String,
        accountName: String,
        vaultID: String,
        itemID: String
    ) -> ProviderCredential {
        ProviderCredential(
            id: "\(accountName)-\(vaultID)-\(itemID)",
            ref: .onePassword(accountName: accountName, vaultID: vaultID, itemID: itemID),
            title: "example.com",
            username: username,
            host: "example.com",
            accountLabel: accountName,
            hasTotp: false
        )
    }
}
