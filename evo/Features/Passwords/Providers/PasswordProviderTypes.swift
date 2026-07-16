import Foundation

/// How to fetch a credential back from its owning provider.
enum ProviderItemRef: Hashable, Sendable {
    case evo(persistentReference: Data)
    case onePassword(accountName: String, vaultID: String, itemID: String)
    case mock(itemID: String)
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

/// Fields Evo can fill across cards and identities. Raw values are the shared vocabulary
/// mirrored by password-manager.js and the Go sidecar's extraction.
enum FieldPurpose: String, Codable, Hashable, Sendable {
    case cardholderName, cardNumber, expMonth, expYear, expDate, cvv
    case givenName, familyName, fullName
    case addressLine1, addressLine2, city, state, postalCode, country
    case phone, email, organization
}

enum StructuredCategory: String, Codable, Hashable, Sendable {
    case creditCard, identity
}

/// Secret-free metadata for a card/identity item surfaced to the overlay.
struct ProviderStructuredItem: Identifiable, Hashable, Sendable {
    let id: String
    let ref: ProviderItemRef
    let category: StructuredCategory
    let title: String
    let subtitle: String
}
