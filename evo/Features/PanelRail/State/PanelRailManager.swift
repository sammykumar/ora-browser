import SwiftUI

/// Per-window state for the right-edge panel rail (supersedes ClaudePanelManager).
/// Radio semantics: at most one panel open. The nested HSplit in `BrowserSplitView`
/// stays mounted and is hidden/shown via `hiddenPanel`, exactly as before.
@MainActor final class PanelRailManager: ObservableObject {
    /// The open panel, or nil when the slot is closed. Single-optional enforces radio exclusivity.
    @Published private(set) var activePanel: SidePanel?

    /// nil = slot visible; .secondary = hidden. Starts hidden; visibility is per-launch, not persisted.
    let hiddenPanel = SideHolder(.secondary)

    /// Shared slot width. Key kept from the walking skeleton so the user's panel width survives.
    let fraction = FractionHolder.usingUserDefaults(0.7, key: "claude.panel.fraction")

    /// Rail chrome visibility — app-wide by design (View → Hide Panel Rail).
    /// @AppStorage doesn't feed objectWillChange; the rail view observes this manager, so publish manually.
    @AppStorage("rail.isVisible") var isRailVisible = true {
        didSet { objectWillChange.send() }
    }

    func toggle(_ panel: SidePanel) {
        if activePanel == panel {
            activePanel = nil
            hiddenPanel.side = .secondary
        } else {
            activePanel = panel        // opens, or swaps content while staying shown
            hiddenPanel.side = nil
        }
    }
}
