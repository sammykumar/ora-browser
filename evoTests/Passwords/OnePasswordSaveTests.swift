@testable import Evo
import Foundation
import Testing

@MainActor
struct OnePasswordSaveTests {
    private final class CaptureTransport: OpHelperTransport {
        var onLine: ((String) -> Void)?
        // Records every method sent (not just the last) because `save` awaits
        // `refresh()` afterward, which issues its own `listItems` request on
        // this same transport and would otherwise clobber a single "last method".
        private(set) var methods: [String] = []
        func send(line: String) throws {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["id"] as? String else { return }
            methods.append(obj["method"] as? String ?? "")
            onLine?("{\"id\":\"\(id)\",\"ok\":true,\"result\":{\"id\":\"new\",\"vaultId\":\"v1\"}}")
        }
        func terminate() {}
    }

    @Test func saveIssuesSaveItem() async throws {
        let transport = CaptureTransport()
        let service = OnePasswordService(transportFactory: { _ in transport })
        service.configureAccounts(["acct"])
        try await service.save(
            url: URL(string: "https://example.com")!, username: "sam", password: "p",
            target: .onePassword(accountName: "acct", vaultID: "v1", existingItemID: nil)
        )
        #expect(transport.methods.contains("saveItem"))
    }
}
