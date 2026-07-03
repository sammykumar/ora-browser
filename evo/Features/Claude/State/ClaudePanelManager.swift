//
//  ClaudePanelManager.swift
//  evo
//
//  Per-window visibility + width state for the Claude side panel (Task 8).
//  Mirrors `SidebarManager`'s use of the vendored SplitView holders: the
//  panel's split fraction persists across launches via `UserDefaults`.
//

import SwiftUI

@MainActor final class ClaudePanelManager: ObservableObject {
    /// Drives the nested HSplit's secondary (right) side in `BrowserSplitView`. `nil` means visible;
    /// `.secondary` means hidden. Starts hidden — the panel is closed by default. Mirrors
    /// `SidebarManager.hiddenSidebar`, which the outer HSplit in the same file uses the same way.
    @Published var hiddenPanel = SideHolder.usingUserDefaults(.secondary, key: "claude.panel.visibility")
    let fraction = FractionHolder.usingUserDefaults(0.7, key: "claude.panel.fraction")

    /// Convenience Bool for menu/UI state, derived from `hiddenPanel` (which remains the source of truth).
    var isVisible: Bool {
        hiddenPanel.side == nil
    }

    func toggle() {
        hiddenPanel.side = hiddenPanel.side == nil ? .secondary : nil
    }
}
