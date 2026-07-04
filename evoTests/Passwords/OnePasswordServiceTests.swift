@testable import Evo
import Foundation
import Testing

@MainActor
struct OnePasswordServiceTests {
    private final class StubTransport: OpHelperTransport {
        var onLine: ((String) -> Void)?
        func send(line: String) throws {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["id"] as? String, let method = obj["method"] as? String
            else { return }
            let result = switch method {
            case "listItems":
                "{\"items\":[{\"id\":\"i1\",\"vaultId\":\"v1\",\"title\":\"GitHub\"," +
                    "\"username\":\"octo\",\"urls\":[\"https://github.com\"],\"hasTotp\":true}]}"
            case "status":
                "{\"state\":\"ready\"}"
            default:
                "{}"
            }
            onLine?("{\"id\":\"\(id)\",\"ok\":true,\"result\":\(result)}")
        }

        func terminate() {}
    }

    @Test func refreshPopulatesCacheAndMatchesByHost() async throws {
        let service = OnePasswordService(transportFactory: { _ in StubTransport() })
        service.configureAccounts(["my.1password.com"])
        await service.refresh()
        #expect(service.metadata.count == 1)
        let matches = try service.credentials(for: #require(URL(string: "https://github.com/login")))
        #expect(matches.first?.username == "octo")
        #expect(matches.first?.accountLabel == "my.1password.com")
        #expect(matches.first?.hasTotp == true)
    }
}
