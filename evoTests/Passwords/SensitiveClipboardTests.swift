import AppKit
@testable import Evo
import Testing

@MainActor
struct SensitiveClipboardTests {
    @Test func clearRunsWhenPasteboardUnchanged() {
        let pasteboard = NSPasteboard.general
        let originalString = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let originalString {
                pasteboard.setString(originalString, forType: .string)
            }
        }

        var scheduled: (() -> Void)?
        ClipboardUtils.copySensitive("123456", clearingAfter: 90) { _, work in scheduled = work }
        let before = pasteboard.string(forType: .string)
        #expect(before == "123456")
        scheduled?() // fire the scheduled clear immediately
        #expect(pasteboard.string(forType: .string) != "123456")
    }

    @Test func clearSkipsWhenPasteboardChanged() {
        let pasteboard = NSPasteboard.general
        let originalString = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let originalString {
                pasteboard.setString(originalString, forType: .string)
            }
        }

        var scheduled: (() -> Void)?
        ClipboardUtils.copySensitive("123456", clearingAfter: 90) { _, work in scheduled = work }
        pasteboard.clearContents()
        pasteboard.setString("user typed something", forType: .string)
        scheduled?()
        #expect(pasteboard.string(forType: .string) == "user typed something")
    }
}
