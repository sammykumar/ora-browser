import AppKit
import SwiftUI

/// Utility functions for clipboard operations
enum ClipboardUtils {
    /// Copies the given text to the system clipboard
    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Triggers copy with animation states
    /// - Parameters:
    ///   - text: The text to copy
    ///   - showCopiedAnimation: Binding to control animation visibility
    ///   - startWheelAnimation: Binding to control wheel animation
    static func triggerCopy(
        _ text: String,
        showCopiedAnimation: Binding<Bool>,
        startWheelAnimation: Binding<Bool>
    ) {
        // Prevent double-trigger if both Command and view shortcut fire
        if showCopiedAnimation.wrappedValue { return }
        copyToClipboard(text)
        withAnimation {
            showCopiedAnimation.wrappedValue = true
            startWheelAnimation.wrappedValue = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation {
                showCopiedAnimation.wrappedValue = false
                startWheelAnimation.wrappedValue = false
            }
        }
    }

    /// Copies text and shows a toast notification
    static func copyWithToast(_ text: String, message: String = "Link copied", toastManager: ToastManager?) {
        copyToClipboard(text)
        toastManager?.show(message, icon: .evo(.copy))
    }

    /// Copies a sensitive value (e.g. a one-time code) to the clipboard, then clears it after
    /// `seconds` — but only if the pasteboard still holds the value we wrote (i.e. the user hasn't
    /// copied something else in the meantime). The `schedule` closure is injectable for testing.
    static func copySensitive(
        _ value: String,
        clearingAfter seconds: TimeInterval,
        schedule: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        let expectedChangeCount = pasteboard.changeCount
        schedule(seconds) {
            let pb = NSPasteboard.general
            guard pb.changeCount == expectedChangeCount, pb.string(forType: .string) == value else { return }
            pb.clearContents()
        }
    }
}
