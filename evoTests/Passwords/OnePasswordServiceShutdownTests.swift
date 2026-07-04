@testable import Evo
import Foundation
import Testing

@MainActor
struct OnePasswordServiceShutdownTests {
    private final class NoopTransport: OpHelperTransport {
        var onLine: ((String) -> Void)?
        func send(line: String) throws {}
        func terminate() {}
    }

    @Test func shutdownAllIsIdempotent() {
        let service = OnePasswordService(transportFactory: { _ in NoopTransport() })
        service.configureAccounts(["a.1password.com"])
        service.shutdownAll()
        service.shutdownAll() // must not crash
        #expect(true)
    }
}
