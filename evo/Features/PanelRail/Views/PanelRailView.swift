import SwiftUI

/// The right-edge vertical icon rail. Window chrome: outermost trailing element,
/// full height, one button per registered SidePanel.
struct PanelRailView: View {
    @EnvironmentObject private var railManager: PanelRailManager
    @EnvironmentObject private var claudeChat: ClaudeChatManager

    var body: some View {
        if railManager.isRailVisible {
            VStack(spacing: 6) {
                ForEach(SidePanel.allCases) { panel in
                    PanelRailButton(
                        panel: panel,
                        isActive: railManager.activePanel == panel,
                        showsActivityDot: activityDot(for: panel),
                        action: { withAnimation { railManager.toggle(panel) } }
                    )
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .frame(width: 40)
            .frame(maxHeight: .infinity)
            .background(.regularMaterial)
        }
    }

    /// A long-running Claude turn stays visible when its panel is closed.
    private func activityDot(for panel: SidePanel) -> Bool {
        panel == .claude && claudeChat.isRunning && railManager.activePanel != .claude
    }
}
