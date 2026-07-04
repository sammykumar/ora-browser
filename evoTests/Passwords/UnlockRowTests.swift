@testable import Evo
import Testing

struct UnlockRowTests {
    @Test func unlockRowExposesLabelAndStableID() {
        let suggestion = PasswordAutofillSuggestion.unlockProvider(label: "1Password")
        #expect(suggestion.id == "unlock-1Password")
        #expect(suggestion.host == "")
    }
}
