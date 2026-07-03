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
    @Published var isVisible = false
    let fraction = FractionHolder.usingUserDefaults(0.7, key: "claude.panel.fraction")

    func toggle() {
        isVisible.toggle()
    }
}
