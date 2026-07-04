import Foundation

/// Wraps `OnePasswordService`, adapting its MainActor-isolated surface to the
/// nonisolated-async shape `PasswordProvider` callers expect.
@MainActor
final class OnePasswordProvider: PasswordProvider {
    private let service: OnePasswordService

    init(service: OnePasswordService = .shared) {
        self.service = service
    }

    nonisolated func credentials(for url: URL, containerID: UUID?) async -> [ProviderCredential] {
        await MainActor.run { service.credentials(for: url) }
    }

    nonisolated func reveal(_ credential: ProviderCredential) async throws -> RevealedCredential {
        try await service.reveal(credential)
    }

    nonisolated func save(url: URL, username: String, password: String, target: SaveTarget) async throws {
        try await service.save(url: url, username: username, password: password, target: target)
    }

    nonisolated func totp(for credential: ProviderCredential) async throws -> String? {
        try await service.totp(for: credential)
    }

    nonisolated var usesBuiltInOverlay: Bool {
        true
    }

    var state: ProviderState {
        service.state
    }
}
