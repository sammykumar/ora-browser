@testable import Evo
import Foundation
import Testing

struct BasicAuthResolveTests {
    @Test func fallsThroughAfterAPriorFailure() {
        // previousFailureCount > 0 must not re-prompt (avoid auth loops).
        #expect(BasicAuthPromptModel.shouldPrompt(matchCount: 2, previousFailureCount: 1) == false)
    }

    @Test func promptsWhenMatchesAndNoPriorFailure() {
        #expect(BasicAuthPromptModel.shouldPrompt(matchCount: 2, previousFailureCount: 0) == true)
    }

    @Test func fallsThroughWhenNoMatches() {
        #expect(BasicAuthPromptModel.shouldPrompt(matchCount: 0, previousFailureCount: 0) == false)
    }
}
