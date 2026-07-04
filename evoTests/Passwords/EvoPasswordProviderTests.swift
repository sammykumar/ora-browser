@testable import Evo
import Foundation
import Testing

struct EvoPasswordProviderTests {
    @Test func mapsSummaryToCredentialWithEvoRef() {
        let metadata = SavedPasswordMetadata(
            id: "abc", origin: "https://example.com", host: "example.com", username: "sam",
            createdAt: .distantPast, updatedAt: .distantPast, lastUsedAt: nil, containerID: nil
        )
        let ref = Data([9, 9])
        let summary = SavedPasswordSummary(metadata: metadata, persistentReference: ref)
        let cred = EvoPasswordProvider.credential(from: summary)
        #expect(cred.id == "abc")
        #expect(cred.host == "example.com")
        #expect(cred.username == "sam")
        #expect(cred.accountLabel == nil)
        guard case let .evo(persistentReference) = cred.ref else {
            Issue.record("expected evo ref")
            return
        }
        #expect(persistentReference == ref)
    }
}
