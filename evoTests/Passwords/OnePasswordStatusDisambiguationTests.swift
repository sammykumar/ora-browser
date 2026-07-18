@testable import Evo
import Testing

struct OnePasswordStatusDisambiguationTests {
    @Test func channelClosedWithAppRunningMeansIntegrationOff() {
        let state = OnePasswordService.disambiguate(errorCode: "channelClosed", appRunning: true)
        #expect(state == .unavailable(reason: "Enable Settings → Developer → Integrate with other apps in 1Password"))
    }

    @Test func channelClosedWithAppNotRunningMeansLaunchIt() {
        let state = OnePasswordService.disambiguate(errorCode: "channelClosed", appRunning: false)
        #expect(state == .unavailable(reason: "1Password isn’t running"))
    }

    @Test func appMissing() {
        let state = OnePasswordService.disambiguate(errorCode: "appMissing", appRunning: false)
        #expect(state == .unavailable(reason: "1Password isn’t installed"))
    }

    @Test func locked() {
        let state = OnePasswordService.disambiguate(errorCode: "locked", appRunning: true)
        #expect(state == .locked)
    }

    @Test func timeoutHintsVaultMayBeLocked() {
        // The onepassword-sdk hangs on a locked vault (#266); our watchdog surfaces that as a
        // "timeout" request failure. It must not fall through to the generic "1Password error" —
        // it should hint that the vault may be locked so the user knows to unlock it.
        let state = OnePasswordService.disambiguate(errorCode: "timeout", appRunning: true)
        guard case let .unavailable(reason) = state else {
            Issue.record("expected .unavailable for timeout, got \(state)")
            return
        }
        #expect(reason.lowercased().contains("lock"))
    }
}
