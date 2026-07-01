import SwiftUI

/// Attach app shortcuts that update as overrides change.
private struct EvoKeyboardShortcutModifier: ViewModifier {
    let shortcut: KeyboardShortcutDefinition
    @EnvironmentObject private var shortcutManager: CustomKeyboardShortcutManager

    func body(content: Content) -> some View {
        content
            .keyboardShortcut(shortcut.keyboardShortcut)
    }
}

/// Attach a tooltip that includes the current shortcut display.
private struct EvoShortcutHelpModifier: ViewModifier {
    let helpText: String
    let shortcut: KeyboardShortcutDefinition
    @EnvironmentObject private var shortcutManager: CustomKeyboardShortcutManager

    func body(content: Content) -> some View {
        content
            .help("\(helpText) (\(shortcut.currentChord.display))")
    }
}

extension View {
    /// Use in place of `.keyboardShortcut` to auto-update on custom shortcut changes.
    func evoShortcut(_ shortcut: KeyboardShortcutDefinition) -> some View {
        modifier(EvoKeyboardShortcutModifier(shortcut: shortcut))
    }

    /// Helper to keep tooltips in sync with the current shortcut mapping.
    /// Results in a tooltip like: "Copy URL (⇧⌘C)"
    func evoShortcutHelp(_ helpText: String, for shortcut: KeyboardShortcutDefinition) -> some View {
        modifier(EvoShortcutHelpModifier(helpText: helpText, shortcut: shortcut))
    }
}
