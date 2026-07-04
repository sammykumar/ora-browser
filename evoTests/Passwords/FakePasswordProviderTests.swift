@testable import Evo
import Foundation
import Testing

struct FakePasswordProviderTests {
    @Test func returnsInjectedCredentials() async throws {
        let cred = ProviderCredential(
            id: "acct:i1", ref: .onePassword(accountName: "acct", vaultID: "v1", itemID: "i1"),
            title: "GitHub", username: "octocat", host: "github.com", accountLabel: "acct", hasTotp: true
        )
        let provider = FakePasswordProvider(credentials: [cred])
        let url = try #require(URL(string: "https://github.com/login"))
        let result = await provider.credentials(for: url, containerID: nil)
        #expect(result.map(\.id) == ["acct:i1"])
    }

    @Test func revealReturnsInjectedSecret() async throws {
        let cred = ProviderCredential(
            id: "acct:i1", ref: .onePassword(accountName: "acct", vaultID: "v1", itemID: "i1"),
            title: "GitHub", username: "octocat", host: "github.com", accountLabel: "acct", hasTotp: false
        )
        let provider = FakePasswordProvider(credentials: [cred], secrets: ["acct:i1": "s3cret"])
        let revealed = try await provider.reveal(cred)
        #expect(revealed.password == "s3cret")
    }
}
