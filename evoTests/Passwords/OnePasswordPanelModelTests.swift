@testable import Evo
import Testing

struct OnePasswordPanelModelTests {
    @Test func readyStatusLists() {
        let line = OnePasswordPanelModel.statusLine(state: .ready, accountCount: 2, itemCount: 869)
        #expect(line == "Connected · 2 accounts · 869 items")
    }

    @Test func lockedStatus() {
        #expect(OnePasswordPanelModel.statusLine(state: .locked, accountCount: 1, itemCount: 0) == "Locked")
    }

    @Test func unavailableStatusShowsReason() {
        let line = OnePasswordPanelModel.statusLine(
            state: .unavailable(reason: "1Password app not set up"),
            accountCount: 0,
            itemCount: 0
        )
        #expect(line == "1Password app not set up")
    }
}
