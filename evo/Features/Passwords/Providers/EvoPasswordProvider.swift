import Foundation

/// Wraps the existing Keychain-backed PasswordManagerService, preserving its behavior
/// (authenticate-on-every-reveal, host matching, email suggestions elsewhere).
final class EvoPasswordProvider: PasswordProvider {
    private let manager = PasswordManagerService.shared

    static func credential(from summary: SavedPasswordSummary) -> ProviderCredential {
        ProviderCredential(
            id: summary.id,
            ref: .evo(persistentReference: summary.persistentReference),
            title: summary.host,
            username: summary.username,
            host: summary.host,
            accountLabel: nil,
            hasTotp: false
        )
    }

    func credentials(for url: URL, containerID: UUID?) async -> [ProviderCredential] {
        manager.matchingEntries(for: url, containerID: containerID).map(Self.credential(from:))
    }

    func reveal(_ credential: ProviderCredential) async throws -> RevealedCredential {
        guard case let .evo(persistentReference) = credential.ref else {
            throw PasswordManagerError.invalidStoredPassword
        }
        let authenticated = await manager.authenticate(
            reason: "Autofill the saved password for \(credential.displayUsername) on \(credential.host)"
        )
        guard authenticated else {
            throw PasswordManagerError.invalidStoredPassword
        }
        let summary = SavedPasswordSummary(
            metadata: SavedPasswordMetadata(
                id: credential.id, origin: nil, host: credential.host, username: credential.username,
                createdAt: .distantPast, updatedAt: .distantPast, lastUsedAt: nil, containerID: nil
            ),
            persistentReference: persistentReference
        )
        let password = try manager.revealPassword(for: summary)
        manager.markUsed(summary)
        return RevealedCredential(username: credential.username, password: password)
    }

    func save(url: URL, username: String, password: String, target: SaveTarget) async throws {
        guard case let .evoContainer(containerID) = target else { return }
        try manager.upsertCredential(for: url, username: username, password: password, containerID: containerID)
    }

    func totp(for credential: ProviderCredential) async throws -> String? {
        nil
    }

    var usesBuiltInOverlay: Bool {
        true
    }

    var state: ProviderState {
        .ready
    }
}
