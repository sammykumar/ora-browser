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
}
