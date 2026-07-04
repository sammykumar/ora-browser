@testable import Evo
import Foundation
import Testing

struct PasswordProviderTypesTests {
    @Test func displayUsernameFallsBackWhenEmpty() {
        let c = ProviderCredential(
            id: "acct:i1", ref: .onePassword(accountName: "acct", vaultID: "v1", itemID: "i1"),
            title: "GitHub", username: "", host: "github.com", accountLabel: "acct", hasTotp: false
        )
        #expect(c.displayUsername == "No username")
    }

    @Test func evoRefRoundTripsPersistentReference() {
        let data = Data([1, 2, 3])
        let ref = ProviderItemRef.evo(persistentReference: data)
        guard case let .evo(persistentReference) = ref else {
            Issue.record("expected evo ref")
            return
        }
        #expect(persistentReference == data)
    }

    @Test func providerStateEquates() {
        #expect(ProviderState.ready == .ready)
        #expect(ProviderState.unavailable(reason: "x") != .unavailable(reason: "y"))
    }
}
