@testable import Evo
import Foundation
import Testing

struct MockPasswordProviderTests {
    @Test func credentialsMatchHost() async {
        let provider = MockPasswordProvider()
        let url = URL(string: "http://127.0.0.1:4599/login-basic.html")
        #expect(url != nil)
        guard let url else { return }
        let creds = await provider.credentials(for: url, containerID: nil)
        #expect(creds.count == 2)
        #expect(creds.allSatisfy { $0.host == "127.0.0.1" })
    }

    @Test func credentialsForUnknownHostAreEmpty() async {
        let provider = MockPasswordProvider()
        guard let url = URL(string: "https://example.org/") else { return }
        let creds = await provider.credentials(for: url, containerID: nil)
        #expect(creds.isEmpty)
    }

    @Test func revealReturnsDeterministicSecret() async throws {
        let provider = MockPasswordProvider()
        guard let url = URL(string: "http://127.0.0.1:4599/") else { return }
        let creds = await provider.credentials(for: url, containerID: nil)
        let alice = creds.first { $0.username == "alice@example.com" }
        #expect(alice != nil)
        guard let alice else { return }
        let revealed = try await provider.reveal(alice)
        #expect(revealed.password == "correct-horse-battery-staple")
    }

    @Test func totpOnlyForTotpCredential() async throws {
        let provider = MockPasswordProvider()
        guard let url = URL(string: "http://localhost:4599/") else { return }
        let creds = await provider.credentials(for: url, containerID: nil)
        #expect(creds.count == 1)
        guard let carol = creds.first else { return }
        #expect(carol.hasTotp)
        let code = try await provider.totp(for: carol)
        #expect(code == "123456")
    }

    @Test func saveIsRecorded() async throws {
        let provider = MockPasswordProvider()
        guard let url = URL(string: "http://127.0.0.1:4599/signup.html") else { return }
        try await provider.save(url: url, username: "new@example.com", password: "pw-1", target: .evoContainer(nil))
        #expect(provider.savedItems.count == 1)
        #expect(provider.savedItems.first?.username == "new@example.com")
    }

    @Test func structuredItemsAndFillValues() async throws {
        let provider = MockPasswordProvider()
        let cards = await provider.structuredItems(.creditCard)
        #expect(cards.count == 1)
        guard let card = cards.first else { return }
        let values = try await provider.fillValues(for: card.ref)
        #expect(values[.cardNumber] == "4111111111111111")
        #expect(values[.cvv] == "123")
        let identities = await provider.structuredItems(.identity)
        #expect(identities.count == 1)
    }
}
