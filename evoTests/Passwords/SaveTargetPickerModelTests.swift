@testable import Evo
import Testing

struct SaveTargetPickerModelTests {
    @Test func defaultsToFirstAccountAndVault() {
        let model = SaveTargetPickerModel(
            accounts: ["personal", "work"],
            vaultsByAccount: ["personal": [("v1", "Private"), ("v2", "Shared")], "work": [("w1", "Team")]]
        )
        #expect(model.defaultAccount == "personal")
        #expect(model.defaultVaultID(for: "personal") == "v1")
    }

    @Test func needsPickerWhenMultipleChoices() {
        let single = SaveTargetPickerModel(accounts: ["a"], vaultsByAccount: ["a": [("v1", "Only")]])
        #expect(single.needsPicker == false)
        let multi = SaveTargetPickerModel(
            accounts: ["a", "b"],
            vaultsByAccount: ["a": [("v1", "x")], "b": [("v2", "y")]]
        )
        #expect(multi.needsPicker == true)
    }
}
