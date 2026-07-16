import Foundation
import Testing
@testable import Evo

struct DebugHarnessHTTPTests {
    private func data(_ s: String) -> Data {
        Data(s.utf8)
    }

    @Test func parsesGetWithQuery() {
        let raw = data("GET /overlay?tab=ABC-123 HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Evo-Harness-Token: tok\r\n\r\n")
        guard case let .request(req) = HarnessHTTPParser.parse(raw) else {
            Issue.record("expected parsed request")
            return
        }
        #expect(req.method == "GET")
        #expect(req.path == "/overlay")
        #expect(req.query["tab"] == "ABC-123")
        #expect(req.headers["x-evo-harness-token"] == "tok")
        #expect(req.body.isEmpty)
    }

    @Test func parsesPostBodyWithContentLength() {
        let body = #"{"url":"http://127.0.0.1:4599/"}"#
        let raw = data("POST /navigate HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)")
        guard case let .request(req) = HarnessHTTPParser.parse(raw) else {
            Issue.record("expected parsed request")
            return
        }
        #expect(req.method == "POST")
        #expect(String(data: req.body, encoding: .utf8) == body)
    }

    @Test func incompleteHeadersReturnIncomplete() {
        let raw = data("GET /health HTTP/1.1\r\nHost: 127")
        guard case .incomplete = HarnessHTTPParser.parse(raw) else {
            Issue.record("expected .incomplete")
            return
        }
    }

    @Test func partialBodyReturnsIncomplete() {
        let raw = data("POST /eval HTTP/1.1\r\nContent-Length: 50\r\n\r\n{\"tabID\":")
        guard case .incomplete = HarnessHTTPParser.parse(raw) else {
            Issue.record("expected .incomplete")
            return
        }
    }

    @Test func garbageIsInvalid() {
        guard case .invalid = HarnessHTTPParser.parse(data("NOT HTTP AT ALL\r\n\r\n")) else {
            Issue.record("expected .invalid")
            return
        }
    }

    @Test func percentDecodesQueryValues() {
        let raw = data("GET /tabs?window=a%20b HTTP/1.1\r\n\r\n")
        guard case let .request(req) = HarnessHTTPParser.parse(raw) else {
            Issue.record("expected parsed request")
            return
        }
        #expect(req.query["window"] == "a b")
    }

    @Test func serializesJSONResponse() {
        let response = HarnessHTTPResponse.json(["ok": true], status: 200)
        let text = String(data: response.serialized(), encoding: .utf8) ?? ""
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Content-Type: application/json"))
        #expect(text.contains("Connection: close"))
        #expect(text.contains(#""ok":true"#))
    }

    @Test func errorResponseCarriesStatusAndMessage() {
        let response = HarnessHTTPResponse.error("unknown tab", status: 404)
        let text = String(data: response.serialized(), encoding: .utf8) ?? ""
        #expect(text.hasPrefix("HTTP/1.1 404 "))
        #expect(text.contains(#""error":"unknown tab""#))
    }
}
