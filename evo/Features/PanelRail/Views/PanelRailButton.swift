import SwiftUI

struct PanelRailButton: View {
    let panel: SidePanel
    let isActive: Bool
    let showsActivityDot: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: panel.symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 30, height: 30)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .overlay(alignment: .topTrailing) {
                    if showsActivityDot {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                            .offset(x: 1, y: -1)
                    }
                }
        }
        .buttonStyle(.plain)
        .help("\(panel.title)  \(panel.shortcutHint)")
        .accessibilityLabel("\(panel.title) panel")
    }
}
