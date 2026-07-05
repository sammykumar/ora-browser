@testable import Evo
import Foundation

final class FakePasswordProvider: PasswordProvider {
    struct SaveCall {
        let url: URL
        let username: String
        let password: String
        let target: SaveTarget
    }

    var injectedCredentials: [ProviderCredential]
    var secrets: [String: String]
    var stateValue: ProviderState
    private(set) var savedCalls: [SaveCall] = []
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
        savedCalls.append(SaveCall(url: url, username: username, password: password, target: target))
    }

    func totp(for credential: ProviderCredential) async throws -> String? {
        credential.hasTotp ? "123456" : nil
    }

    func structuredItems(_ category: StructuredCategory) async -> [ProviderStructuredItem] {
        []
    }

    func fillValues(for ref: ProviderItemRef) async throws -> [FieldPurpose: String] {
        [:]
    }

    var usesBuiltInOverlay: Bool {
        true
    }

    var state: ProviderState {
        stateValue
    }
}
