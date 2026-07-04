@testable import Evo
import Foundation
import Testing

@MainActor
struct OnePasswordAccountsSettingTests {
    @Test func addAndRemoveDedupe() {
        let store = SettingsStore.shared
        let snapshot = store.onePasswordAccounts
        defer { store.setOnePasswordAccounts(snapshot) }

        store.setOnePasswordAccounts([])
        store.addOnePasswordAccount("my.1password.com")
        store.addOnePasswordAccount("my.1password.com") // dupe ignored
        #expect(store.onePasswordAccounts == ["my.1password.com"])
        store.removeOnePasswordAccount("my.1password.com")
        #expect(store.onePasswordAccounts.isEmpty)
    }
}
