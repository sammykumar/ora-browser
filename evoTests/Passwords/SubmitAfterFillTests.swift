@testable import Evo
import Foundation
import Testing

struct SubmitAfterFillTests {
    private func focus(action: PasswordFormAction, passwordFieldIDs: [String]) -> PasswordBridgeFocusPayload {
        PasswordBridgeFocusPayload(
            fieldID: "f", hostname: "login.microsoftonline.com", action: action, fieldKind: .username,
            usernameFieldID: "u", passwordFieldIDs: passwordFieldIDs,
            rect: PasswordBridgeRect(originX: 0, originY: 0, width: 1, height: 1)
        )
    }

    @Test func submitsWhenLoginPasswordFieldFilled() {
        let f = focus(action: .login, passwordFieldIDs: ["p"])
        #expect(PasswordAutofillCoordinator.shouldSubmitAfterFill(focus: f, submitEnabled: true))
    }

    @Test func doesNotSubmitUsernameOnlyStep() {
        // Microsoft's first sign-in step is username-only (no password field). Auto-submitting it
        // fires before the SPA serializes the value → AADSTS90100 "login parameter is empty". Bug 3.
        let f = focus(action: .login, passwordFieldIDs: [])
        #expect(!PasswordAutofillCoordinator.shouldSubmitAfterFill(focus: f, submitEnabled: true))
    }

    @Test func doesNotSubmitWhenSettingDisabled() {
        let f = focus(action: .login, passwordFieldIDs: ["p"])
        #expect(!PasswordAutofillCoordinator.shouldSubmitAfterFill(focus: f, submitEnabled: false))
    }

    @Test func doesNotSubmitCreateAccount() {
        let f = focus(action: .createAccount, passwordFieldIDs: ["p"])
        #expect(!PasswordAutofillCoordinator.shouldSubmitAfterFill(focus: f, submitEnabled: true))
    }
}
