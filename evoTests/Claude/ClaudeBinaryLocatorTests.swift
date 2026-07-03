@testable import Evo
import Testing

struct ClaudeBinaryLocatorTests {
    @Test func prefersValidOverride() {
        let r = ClaudeBinaryLocator.resolve(override: "/opt/claude", runWhich: { nil })
        #expect(r == .success("/opt/claude"))
    }

    @Test func fallsBackToWhich() {
        let r = ClaudeBinaryLocator.resolve(override: nil, runWhich: { "/usr/local/bin/claude" })
        #expect(r == .success("/usr/local/bin/claude"))
    }

    @Test func ignoresBlankOverride() {
        let r = ClaudeBinaryLocator.resolve(override: "   ", runWhich: { "/x/claude" })
        #expect(r == .success("/x/claude"))
    }

    @Test func failsWhenNothingFound() {
        let r = ClaudeBinaryLocator.resolve(override: nil, runWhich: { nil })
        #expect(r == .failure(.notFound))
    }
}
