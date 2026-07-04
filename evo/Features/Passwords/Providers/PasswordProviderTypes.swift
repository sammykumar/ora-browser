import Foundation

/// How to fetch a credential back from its owning provider.
enum ProviderItemRef: Hashable, Sendable {
    case evo(persistentReference: Data)
    case onePassword(accountName: String, vaultID: String, itemID: String)
}

/// A provider-agnostic credential surfaced to the autofill overlay. Carries NO secret.
struct ProviderCredential: Identifiable, Hashable, Sendable {
    let id: String
    let ref: ProviderItemRef
    let title: String
    let username: String
    let host: String
    let accountLabel: String?
    let hasTotp: Bool

    var displayUsername: String {
        username.isEmpty ? "No username" : username
    }
}

struct RevealedCredential: Sendable {
    let username: String
    let password: String
}

/// Where a save/update should land.
enum SaveTarget: Sendable {
    case evoContainer(UUID?)
    case onePassword(accountName: String, vaultID: String, existingItemID: String?)
}

/// UI-facing provider status.
enum ProviderState: Equatable, Sendable {
    case ready
    case locked
    case syncing
    case unavailable(reason: String)
}
