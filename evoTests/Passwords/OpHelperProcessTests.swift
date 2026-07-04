@testable import Evo
import Foundation
import Testing

private final class EchoTransport: OpHelperTransport {
    var onLine: ((String) -> Void)?
    func send(line: String) throws {
        // Parse the request, echo a success response with the same id.
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? String
        else { return }
        let resp = "{\"id\":\"\(id)\",\"ok\":true,\"result\":{\"echo\":true}}"
        onLine?(resp)
    }

    func terminate() {}
}

struct OpHelperProcessTests {
    @Test func correlatesResponseToRequestByID() async throws {
        let transport = EchoTransport()
        let helper = OpHelperProcess(transport: transport)
        let result = try await helper.request(method: "status", params: [:])
        #expect((result["echo"] as? Bool) == true)
    }
}
