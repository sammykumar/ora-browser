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
}
