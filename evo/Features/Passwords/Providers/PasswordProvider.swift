import Foundation

/// The seam that makes password backends first-class. Evo Keychain and 1Password both implement it.
protocol PasswordProvider: AnyObject {
    func credentials(for url: URL, containerID: UUID?) async -> [ProviderCredential]
    func reveal(_ credential: ProviderCredential) async throws -> RevealedCredential
    func save(url: URL, username: String, password: String, target: SaveTarget) async throws
    func totp(for credential: ProviderCredential) async throws -> String?
    var usesBuiltInOverlay: Bool { get }
    var state: ProviderState { get }
}
