#if DEBUG
    import Foundation

    /// Deterministic in-memory provider for the debug harness. Never touches Keychain or 1Password.
    /// Vault contents are fixed constants so harness assertions are stable across runs.
    final class MockPasswordProvider: PasswordProvider {
        struct SavedItem: Equatable {
            let url: URL
            let username: String
            let password: String
        }

        private struct MockLogin {
            let id: String
            let title: String
            let username: String
            let password: String
            let host: String
            let totp: String?
        }

        private let logins: [MockLogin] = [
            MockLogin(
                id: "mock-login-alice",
                title: "Fixture Site A",
                username: "alice@example.com",
                password: "correct-horse-battery-staple",
                host: "127.0.0.1",
                totp: nil
            ),
            MockLogin(
                id: "mock-login-bob",
                title: "Fixture Site A (alt)",
                username: "bob@example.com",
                password: "hunter2-bob",
                host: "127.0.0.1",
                totp: nil
            ),
            MockLogin(
                id: "mock-login-carol",
                title: "Fixture Site B",
                username: "carol@example.com",
                password: "carol-pass-3",
                host: "localhost",
                totp: "123456"
            )
        ]

        private(set) var savedItems: [SavedItem] = []

        var usesBuiltInOverlay: Bool {
            true
        }

        var state: ProviderState {
            .ready
        }

        func credentials(for url: URL, containerID _: UUID?) async -> [ProviderCredential] {
            guard let host = url.host else { return [] }
            return logins.filter { $0.host == host }.map { login in
                ProviderCredential(
                    id: login.id,
                    ref: .mock(itemID: login.id),
                    title: login.title,
                    username: login.username,
                    host: login.host,
                    accountLabel: "Mock Vault",
                    hasTotp: login.totp != nil
                )
            }
        }

        func reveal(_ credential: ProviderCredential) async throws -> RevealedCredential {
            guard case let .mock(itemID) = credential.ref,
                  let login = logins.first(where: { $0.id == itemID })
            else {
                throw MockProviderError.itemNotFound
            }
            return RevealedCredential(username: login.username, password: login.password)
        }

        func save(url: URL, username: String, password: String, target _: SaveTarget) async throws {
            savedItems.append(SavedItem(url: url, username: username, password: password))
        }

        func totp(for credential: ProviderCredential) async throws -> String? {
            guard case let .mock(itemID) = credential.ref else { return nil }
            return logins.first(where: { $0.id == itemID })?.totp
        }

        func structuredItems(_ category: StructuredCategory) async -> [ProviderStructuredItem] {
            switch category {
            case .creditCard:
                return [ProviderStructuredItem(
                    id: "mock-card-visa",
                    ref: .mock(itemID: "mock-card-visa"),
                    category: .creditCard,
                    title: "Mock Visa",
                    subtitle: "•••• 1111"
                )]
            case .identity:
                return [ProviderStructuredItem(
                    id: "mock-identity-alice",
                    ref: .mock(itemID: "mock-identity-alice"),
                    category: .identity,
                    title: "Alice Mock",
                    subtitle: "1 Fixture Way"
                )]
            }
        }

        func fillValues(for ref: ProviderItemRef) async throws -> [FieldPurpose: String] {
            guard case let .mock(itemID) = ref else { throw MockProviderError.itemNotFound }
            switch itemID {
            case "mock-card-visa":
                return [
                    .cardholderName: "Alice Mock",
                    .cardNumber: "4111111111111111",
                    .expMonth: "12",
                    .expYear: "2030",
                    .expDate: "12/2030",
                    .cvv: "123"
                ]
            case "mock-identity-alice":
                return [
                    .givenName: "Alice",
                    .familyName: "Mock",
                    .fullName: "Alice Mock",
                    .addressLine1: "1 Fixture Way",
                    .city: "Testville",
                    .state: "CA",
                    .postalCode: "94100",
                    .country: "US",
                    .phone: "+1 555 010 0001",
                    .email: "alice@example.com",
                    .organization: "SK Productions"
                ]
            default:
                throw MockProviderError.itemNotFound
            }
        }
    }

    enum MockProviderError: Error {
        case itemNotFound
    }
#endif
