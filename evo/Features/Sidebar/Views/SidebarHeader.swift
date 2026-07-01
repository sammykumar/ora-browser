//
//  SidebarHeader.swift
//  evo
//

import SwiftUI

struct SidebarHeader: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var sidebarManager: SidebarManager
    @EnvironmentObject var toolbarManager: ToolbarManager

    private var sidebarIcon: String {
        sidebarManager.sidebarPosition == .secondary ? "sidebar.right" : "sidebar.left"
    }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarManager.sidebarPosition != .secondary, !appState.isFullscreen {
                WindowControls(isFullscreen: appState.isFullscreen)
                    .frame(height: 30)
            }

            if toolbarManager.isToolbarHidden {
                HStack(spacing: 0) {
                    if sidebarManager.sidebarPosition == .primary {
                        URLBarButton(
                            systemName: sidebarIcon,
                            isEnabled: true,
                            foregroundColor: theme.foreground.opacity(0.7),
                            action: { sidebarManager.toggleSidebar() }
                        )
                        .evoShortcutHelp("Toggle Sidebar", for: KeyboardShortcuts.App.toggleSidebar)
                        Spacer()
                    }

                    URLBarButton(
                        systemName: "chevron.left",
                        isEnabled: tabManager.activeTab?.canGoBack ?? false,
                        foregroundColor: theme.foreground.opacity(0.7),
                        action: {
                            if let activeTab = tabManager.activeTab {
                                activeTab.goBack()
                            }
                        }
                    )
                    .evoShortcutHelp("Go Back", for: KeyboardShortcuts.Navigation.back)

                    URLBarButton(
                        systemName: "chevron.right",
                        isEnabled: tabManager.activeTab?.canGoForward ?? false,
                        foregroundColor: theme.foreground.opacity(0.7),
                        action: {
                            if let activeTab = tabManager.activeTab {
                                activeTab.goForward()
                            }
                        }
                    )
                    .evoShortcutHelp("Go Forward", for: KeyboardShortcuts.Navigation.forward)

                    URLBarButton(
                        systemName: "arrow.clockwise",
                        isEnabled: tabManager.activeTab != nil,
                        foregroundColor: theme.foreground.opacity(0.7),
                        action: {
                            if let activeTab = tabManager.activeTab {
                                activeTab.reload()
                            }
                        }
                    )
                    .evoShortcutHelp("Reload This Page", for: KeyboardShortcuts.Navigation.reload)

                    if sidebarManager.sidebarPosition == .secondary {
                        Spacer()
                        URLBarButton(
                            systemName: sidebarIcon,
                            isEnabled: true,
                            foregroundColor: theme.foreground.opacity(0.7),
                            action: { sidebarManager.toggleSidebar() }
                        )
                        .evoShortcutHelp("Toggle Sidebar", for: KeyboardShortcuts.App.toggleSidebar)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 38)
    }
}
