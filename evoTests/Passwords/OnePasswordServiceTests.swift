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

    @Test func doesNotMatchLookalikeOrSubstringHosts() async throws {
        let service = OnePasswordService(transportFactory: { _ in StubTransport() })
        service.configureAccounts(["my.1password.com"])
        await service.refresh()
        #expect(try service.credentials(for: #require(URL(string: "https://evil.com/?ref=github.com"))).isEmpty)
        #expect(try service.credentials(for: #require(URL(string: "https://not-github.com/login"))).isEmpty)
        #expect(try service.credentials(for: #require(URL(string: "https://github.com.evil.com/login"))).isEmpty)
        #expect(try service.credentials(for: #require(URL(string: "https://github.com/login"))).count == 1)
    }

    @Test func ensureConfiguredIsIdempotentAndPopulatesFromSetting() async {
        let store = SettingsStore.shared
        let baselineAccountName = store.onePasswordAccountName
        store.onePasswordAccountName = "my.1password.com"
        defer { store.onePasswordAccountName = baselineAccountName }

        let service = OnePasswordService(transportFactory: { _ in StubTransport() })

        await service.ensureConfigured()
        #expect(service.metadata.count == 1)

        // A second call must not re-configure or double the cached metadata — the
        // in-flight/one-time guard should make this a no-op against the warm cache.
        await service.ensureConfigured()
        #expect(service.metadata.count == 1)
    }
}
