@testable import Evo
import Foundation
import Testing

@MainActor
struct OnePasswordProviderTests {
    private final class StubTransport: OpHelperTransport {
        var onLine: ((String) -> Void)?
        func send(line: String) throws {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["id"] as? String, let method = obj["method"] as? String else { return }
            let result = method == "listItems"
                ? "{\"items\":[{\"id\":\"i1\",\"vaultId\":\"v1\",\"title\":\"GitHub\"," +
                "\"username\":\"octo\",\"urls\":[\"https://github.com\"],\"hasTotp\":false}]}"
                : "{}"
            onLine?("{\"id\":\"\(id)\",\"ok\":true,\"result\":\(result)}")
        }

        func terminate() {}
    }

    @Test func credentialsComeFromService() async throws {
        let service = OnePasswordService(transportFactory: { _ in StubTransport() })
        service.configureAccounts(["my.1password.com"])
        await service.refresh()
        let provider = OnePasswordProvider(service: service)
        let matches = try await provider.credentials(for: #require(URL(string: "https://github.com")), containerID: nil)
        #expect(matches.first?.id == "my.1password.com:i1")
    }
}
