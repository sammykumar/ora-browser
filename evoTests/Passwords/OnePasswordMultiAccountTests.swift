@testable import Evo
import Foundation
import Testing

@MainActor
struct OnePasswordMultiAccountTests {
    private final class OneItemTransport: OpHelperTransport {
        let account: String
        var onLine: ((String) -> Void)?
        init(account: String) {
            self.account = account
        }

        func send(line: String) throws {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["id"] as? String, let method = obj["method"] as? String else { return }
            let result = method == "listItems"
                ? "{\"items\":[{\"id\":\"i-\(account)\",\"vaultId\":\"v1\",\"title\":\"GitHub\"," +
                "\"username\":\"u-\(account)\",\"urls\":[\"https://github.com\"],\"hasTotp\":false}]}"
                : "{}"
            onLine?("{\"id\":\"\(id)\",\"ok\":true,\"result\":\(result)}")
        }

        func terminate() {}
    }

    @Test func twoAccountsMergeWithBadges() async {
        let service = OnePasswordService(transportFactory: { OneItemTransport(account: $0) })
        service.configureAccounts(["personal", "work"])
        await service.refresh()
        let labels = Set(service.metadata.compactMap(\.accountLabel))
        #expect(labels == ["personal", "work"])
        #expect(service.metadata.count == 2)
    }

    private final class DuplicateItemsTransport: OpHelperTransport {
        var onLine: ((String) -> Void)?
        func send(line: String) throws {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["id"] as? String, let method = obj["method"] as? String else { return }
            // Two distinct vault items with identical host + username, e.g. the
            // same login duplicated across vaults within one account.
            let result = method == "listItems"
                ? "{\"items\":[" +
                "{\"id\":\"i1\",\"vaultId\":\"v1\",\"title\":\"GitHub\"," +
                "\"username\":\"octo\",\"urls\":[\"https://github.com\"],\"hasTotp\":false}," +
                "{\"id\":\"i2\",\"vaultId\":\"v2\",\"title\":\"GitHub (copy)\"," +
                "\"username\":\"octo\",\"urls\":[\"https://github.com\"],\"hasTotp\":false}" +
                "]}"
                : "{}"
            onLine?("{\"id\":\"\(id)\",\"ok\":true,\"result\":\(result)}")
        }

        func terminate() {}
    }

    @Test func dedupeCollapsesIdenticalHostUsernameAccount() async {
        // Two vault items surfacing the identical (host, username, account) triple
        // should collapse to a single merged credential.
        let service = OnePasswordService(transportFactory: { _ in DuplicateItemsTransport() })
        service.configureAccounts(["personal"])
        await service.refresh()
        #expect(service.metadata.count == 1)
        #expect(service.metadata.first?.accountLabel == "personal")
    }
}
