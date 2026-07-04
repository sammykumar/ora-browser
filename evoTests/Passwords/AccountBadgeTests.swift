@testable import Evo
import Foundation
import Testing

struct AccountBadgeTests {
    @Test func badgeShortensAccountDomain() {
        let cred = ProviderCredential(
            id: "my.1password.com:i1",
            ref: .onePassword(accountName: "my.1password.com", vaultID: "v", itemID: "i1"),
            title: "GitHub", username: "u", host: "github.com", accountLabel: "my.1password.com", hasTotp: false
        )
        #expect(accountBadgeText(for: cred) == "my")
    }

    @Test func noBadgeForEvo() {
        let cred = ProviderCredential(
            id: "x", ref: .evo(persistentReference: Data()),
            title: "t", username: "u", host: "h", accountLabel: nil, hasTotp: false
        )
        #expect(accountBadgeText(for: cred) == nil)
    }
}
