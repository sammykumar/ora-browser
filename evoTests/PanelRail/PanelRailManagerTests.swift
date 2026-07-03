@testable import Evo
import Testing

@MainActor struct PanelRailManagerTests {
    @Test func startsClosedAndHidden() {
        let manager = PanelRailManager()
        #expect(manager.activePanel == nil)
        #expect(manager.hiddenPanel.side == .secondary)
    }

    @Test func toggleOpensPanelAndShowsSide() {
        let manager = PanelRailManager()
        manager.toggle(.claude)
        #expect(manager.activePanel == .claude)
        #expect(manager.hiddenPanel.side == nil)
    }

    @Test func toggleSamePanelClosesAndHides() {
        let manager = PanelRailManager()
        manager.toggle(.claude)
        manager.toggle(.claude)
        #expect(manager.activePanel == nil)
        #expect(manager.hiddenPanel.side == .secondary)
    }

    @Test func registryHasStableClaudeMetadata() {
        #expect(SidePanel.claude.id == "claude")
        #expect(SidePanel.claude.symbol == "sparkles")
        #expect(SidePanel.allCases.contains(.claude))
    }
}
