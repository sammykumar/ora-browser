@testable import Evo
import Foundation
import Testing

@MainActor
struct ActiveProviderTests {
    @Test func evoKindReturnsEvoProvider() {
        let registry = PasswordManagerProviderRegistry.shared
        let provider = registry.activeProvider(for: .evo)
        #expect(provider is EvoPasswordProvider)
    }

    @Test func onePasswordKindReturnsOnePasswordProvider() {
        let registry = PasswordManagerProviderRegistry.shared
        let provider = registry.activeProvider(for: .onePassword)
        #expect(provider is OnePasswordProvider)
    }

    @Test func onePasswordDescriptorIsAvailableAndUsesOverlay() {
        let descriptor = PasswordManagerProviderRegistry.shared.descriptor(for: .onePassword)
        #expect(descriptor.isAvailable)
        #expect(descriptor.usesBuiltInOverlay)
    }
}
