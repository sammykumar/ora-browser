import Foundation

enum PasswordManagerProviderKind: String, CaseIterable, Codable, Identifiable {
    case evo
    case onePassword
    case bitwarden
    case mock

    var id: String {
        rawValue
    }
}

enum PasswordManagerAutofillMode {
    case builtInOverlay
    case nativeProviderOverlay
}

struct PasswordManagerProviderDescriptor: Identifiable, Hashable {
    let kind: PasswordManagerProviderKind
    let title: String
    let summary: String
    let vaultStoredInEvo: Bool
    let autofillMode: PasswordManagerAutofillMode
    let isAvailable: Bool

    var id: PasswordManagerProviderKind {
        kind
    }

    var usesBuiltInVault: Bool {
        vaultStoredInEvo
    }

    var usesBuiltInOverlay: Bool {
        autofillMode == .builtInOverlay
    }
}

final class PasswordManagerProviderRegistry {
    static let shared = PasswordManagerProviderRegistry()

    let providers: [PasswordManagerProviderDescriptor] = {
        var list: [PasswordManagerProviderDescriptor] = [
            PasswordManagerProviderDescriptor(
                kind: .evo,
                title: "Evo Passwords",
                summary: "Store encrypted credentials in Evo and show Evo's autofill overlay.",
                vaultStoredInEvo: true,
                autofillMode: .builtInOverlay,
                isAvailable: true
            ),
            PasswordManagerProviderDescriptor(
                kind: .onePassword,
                title: "1Password",
                summary: "Autofill from your 1Password vaults using the 1Password desktop app.",
                vaultStoredInEvo: false,
                autofillMode: .builtInOverlay,
                isAvailable: true
            )
            // PasswordManagerProviderDescriptor(
            //     kind: .bitwarden,
            //     title: "Bitwarden",
            //     summary: "Reserved for a native Bitwarden integration with Bitwarden's own autofill surface.",
            //     vaultStoredInEvo: false,
            //     autofillMode: .nativeProviderOverlay,
            //     isAvailable: false
            // )
        ]
        #if DEBUG
            list.append(PasswordManagerProviderDescriptor(
                kind: .mock,
                title: "Mock (Debug)",
                summary: "Deterministic fake vault for the debug harness. Debug builds only.",
                vaultStoredInEvo: false,
                autofillMode: .builtInOverlay,
                isAvailable: true
            ))
        #endif
        return list
    }()

    private lazy var evoProvider = EvoPasswordProvider()

    @MainActor private lazy var onePasswordProvider = OnePasswordProvider()

    #if DEBUG
        @MainActor private lazy var mockProvider = MockPasswordProvider()
    #endif

    private init() {}

    func descriptor(for kind: PasswordManagerProviderKind) -> PasswordManagerProviderDescriptor {
        providers.first(where: { $0.kind == kind }) ?? providers[0]
    }

    @MainActor
    func activeProvider(for kind: PasswordManagerProviderKind) -> PasswordProvider {
        switch kind {
        #if DEBUG
            case .mock: return mockProvider
        #endif
        case .onePassword: return onePasswordProvider
        default: return evoProvider
        }
    }
}
