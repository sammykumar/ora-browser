import Foundation

/// The closed registry of side panels shown on the right-edge rail.
/// Adding a panel = add a case here + a view branch in `BrowserSplitView.panelSlot()`
/// (the exhaustive switch there makes forgetting the view a compile error).
enum SidePanel: String, CaseIterable, Identifiable {
    case claude

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .claude: "Claude"
        }
    }

    var symbol: String {
        switch self {
        case .claude: "sparkles"
        }
    }

    /// Tooltip hint only — the actual key binding lives in `EvoCommands`.
    var shortcutHint: String {
        switch self {
        case .claude: "⌥⌘C"
        }
    }
}
