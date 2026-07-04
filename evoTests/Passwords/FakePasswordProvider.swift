@testable import Evo
import Foundation

final class FakePasswordProvider: PasswordProvider {
    var injectedCredentials: [ProviderCredential]
    var secrets: [String: String]
    var stateValue: ProviderState
    private(set) var savedCalls: [(url: URL, username: String, password: String, target: SaveTarget)] = []
    private(set) var revealCalls: [String] = []

    init(credentials: [ProviderCredential] = [], secrets: [String: String] = [:], state: ProviderState = .ready) {
        injectedCredentials = credentials
        self.secrets = secrets
        stateValue = state
    }

    func credentials(for url: URL, containerID: UUID?) async -> [ProviderCredential] {
        guard let host = url.host else { return [] }
        return injectedCredentials.filter { $0.host == host }
    }

    func reveal(_ credential: ProviderCredential) async throws -> RevealedCredential {
        revealCalls.append(credential.id)
        return RevealedCredential(username: credential.username, password: secrets[credential.id] ?? "")
    }

    func save(url: URL, username: String, password: String, target: SaveTarget) async throws {
        savedCalls.append((url, username, password, target))
    }

    func totp(for credential: ProviderCredential) async throws -> String? {
        credential.hasTotp ? "123456" : nil
    }

    var usesBuiltInOverlay: Bool {
        true
    }

    var state: ProviderState {
        stateValue
    }
}
