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

    private final class CountingStubTransport: OpHelperTransport {
        var onLine: ((String) -> Void)?
        private(set) var listItemsCalls = 0

        func send(line: String) throws {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["id"] as? String, let method = obj["method"] as? String
            else { return }
            if method == "listItems" { listItemsCalls += 1 }
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
        let baselineAccounts = store.onePasswordAccounts
        store.setOnePasswordAccounts(["my.1password.com"])
        defer { store.setOnePasswordAccounts(baselineAccounts) }

        let transport = CountingStubTransport()
        let service = OnePasswordService(transportFactory: { _ in transport })

        await service.ensureConfigured()
        #expect(service.metadata.count == 1)

        // A second call must not re-configure or double the cached metadata — the
        // in-flight/one-time guard should make this a no-op against the warm cache.
        await service.ensureConfigured()
        #expect(service.metadata.count == 1)
        #expect(transport.listItemsCalls == 1) // guard prevented a second spawn+refresh
    }

    private final class TotpStubTransport: OpHelperTransport {
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
            case "totp":
                "{\"code\":\"123456\"}"
            default:
                "{}"
            }
            onLine?("{\"id\":\"\(id)\",\"ok\":true,\"result\":\(result)}")
        }

        func terminate() {}
    }

    @Test func totpReturnsSidecarCode() async throws {
        let service = OnePasswordService(transportFactory: { _ in TotpStubTransport() })
        service.configureAccounts(["my.1password.com"])
        await service.refresh()
        let url = try #require(URL(string: "https://github.com/login"))
        let credential = try #require(service.credentials(for: url).first)
        let code = try await service.totp(for: credential)
        #expect(code == "123456")
    }

    @Test func configureAccountsRecreatesSidecarOnReconnect() {
        var factoryCalls = 0
        let service = OnePasswordService(transportFactory: { _ in
            factoryCalls += 1
            return StubTransport()
        })

        service.configureAccounts(["acct"])
        #expect(factoryCalls == 1)

        // Simulates Reconnect after the Go watchdog killed a dead sidecar: the
        // stale process must not be reused — a fresh transport must be spawned.
        service.configureAccounts(["acct"])
        #expect(factoryCalls == 2)
    }

    private final class WireErrorTransport: OpHelperTransport {
        var onLine: ((String) -> Void)?
        func send(line: String) throws {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["id"] as? String, let method = obj["method"] as? String
            else { return }
            if method == "listItems" {
                onLine?("{\"id\":\"\(id)\",\"ok\":false,\"error\":{\"code\":\"channelClosed\",\"message\":\"nope\"}}")
            } else {
                onLine?("{\"id\":\"\(id)\",\"ok\":true,\"result\":{}}")
            }
        }

        func terminate() {}
    }

    @Test func ensureConfiguredRetriesAfterFailedFirstAttempt() async {
        let store = SettingsStore.shared
        let baselineAccounts = store.onePasswordAccounts
        store.setOnePasswordAccounts(["my.1password.com"])
        defer { store.setOnePasswordAccounts(baselineAccounts) }

        var factoryCalls = 0
        let service = OnePasswordService(transportFactory: { _ in
            factoryCalls += 1
            return WireErrorTransport()
        })

        await service.ensureConfigured()
        #expect(factoryCalls == 1)
        #expect(service.metadata.isEmpty) // first attempt failed — never reached "ready"

        // Because the first attempt didn't land in `.ready`/`.locked`, the one-shot guard
        // must have been cleared, so a second call retries (spawns a fresh sidecar) rather
        // than being a permanent no-op.
        await service.ensureConfigured()
        #expect(factoryCalls == 2)
    }
}
