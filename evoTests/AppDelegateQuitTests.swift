import AppKit
@testable import Evo
import Testing

struct AppDelegateQuitTests {
    @Test func confirmsWhenEnabledAndWindowVisible() {
        #expect(AppDelegate.terminateReply(confirmBeforeQuit: true, hasVisibleWindow: true) == .terminateLater)
    }

    @Test func quitsImmediatelyWhenConfirmationDisabled() {
        #expect(AppDelegate.terminateReply(confirmBeforeQuit: false, hasVisibleWindow: true) == .terminateNow)
    }

    @Test func quitsImmediatelyWhenNoWindow() {
        // No window to host the confirmation dialog → terminate now regardless of the setting.
        #expect(AppDelegate.terminateReply(confirmBeforeQuit: true, hasVisibleWindow: false) == .terminateNow)
        #expect(AppDelegate.terminateReply(confirmBeforeQuit: false, hasVisibleWindow: false) == .terminateNow)
    }
}
