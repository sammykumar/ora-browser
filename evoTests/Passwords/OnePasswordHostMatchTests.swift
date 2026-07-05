@testable import Evo
import Foundation
import Testing

@MainActor
struct OnePasswordHostMatchTests {
    @Test func exactHostsMatch() {
        #expect(OnePasswordService.hostsMatch(pageHost: "github.com", credentialHost: "github.com"))
    }

    @Test func pageIsSubdomainOfCredential() {
        #expect(OnePasswordService.hostsMatch(pageHost: "accounts.google.com", credentialHost: "google.com"))
    }

    @Test func credentialIsSubdomainOfPage() {
        #expect(OnePasswordService.hostsMatch(pageHost: "google.com", credentialHost: "accounts.google.com"))
    }

    @Test func lookalikeHostsDoNotMatch() {
        #expect(!OnePasswordService.hostsMatch(pageHost: "evil.com", credentialHost: "github.com"))
        #expect(!OnePasswordService.hostsMatch(pageHost: "notgithub.com", credentialHost: "github.com"))
        #expect(!OnePasswordService.hostsMatch(pageHost: "github.com.evil.com", credentialHost: "github.com"))
        #expect(!OnePasswordService.hostsMatch(pageHost: "github.com", credentialHost: "com"))
        #expect(!OnePasswordService.hostsMatch(pageHost: "evilgoogle.com", credentialHost: "google.com"))
    }

    private final class SubdomainStubTransport: OpHelperTransport {
        var onLine: ((String) -> Void)?
        func send(line: String) throws {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["id"] as? String, let method = obj["method"] as? String
            else { return }
            let result = switch method {
            case "listItems":
                "{\"items\":[{\"id\":\"i1\",\"vaultId\":\"v1\",\"title\":\"Google\"," +
                    "\"username\":\"sam\",\"urls\":[\"https://google.com\"],\"hasTotp\":false}]}"
            case "status":
                "{\"state\":\"ready\"}"
            default:
                "{}"
            }
            onLine?("{\"id\":\"\(id)\",\"ok\":true,\"result\":\(result)}")
        }

        func terminate() {}
    }

    @Test func credentialsForMatchesSubdomainAndRejectsLookalike() async throws {
        let service = OnePasswordService(transportFactory: { _ in SubdomainStubTransport() })
        service.configureAccounts(["my.1password.com"])
        await service.refresh()

        let subdomainMatches = try service.credentials(for: #require(URL(string: "https://accounts.google.com/signin")))
        #expect(subdomainMatches.count == 1)
        #expect(subdomainMatches.first?.username == "sam")

        let lookalikeMatches = try service.credentials(for: #require(URL(string: "https://evil.com/")))
        #expect(lookalikeMatches.isEmpty)
    }
}
