#if DEBUG
    import Foundation

    struct HarnessHTTPRequest {
        let method: String
        let path: String
        let query: [String: String]
        let headers: [String: String]
        let body: Data
    }

    enum HarnessParseResult {
        case incomplete
        case invalid
        case request(HarnessHTTPRequest)
    }

    enum HarnessHTTPParser {
        private static let headerTerminator = Data("\r\n\r\n".utf8)

        static func parse(_ data: Data) -> HarnessParseResult {
            guard let headerEnd = data.range(of: headerTerminator) else {
                // A request line longer than 16 KB without a terminator is garbage, not "still arriving".
                return data.count > 16384 ? .invalid : .incomplete
            }
            guard let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else {
                return .invalid
            }
            var lines = head.components(separatedBy: "\r\n")
            guard !lines.isEmpty else { return .invalid }
            let requestLine = lines.removeFirst().components(separatedBy: " ")
            guard requestLine.count == 3,
                  requestLine[2].hasPrefix("HTTP/"),
                  ["GET", "POST"].contains(requestLine[0])
            else {
                return .invalid
            }

            var headers: [String: String] = [:]
            for line in lines {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }

            let contentLength = Int(headers["content-length"] ?? "0") ?? 0
            let bodyStart = headerEnd.upperBound
            let availableBody = data.count - bodyStart
            guard availableBody >= contentLength else { return .incomplete }
            let body = data.subdata(in: bodyStart ..< bodyStart + contentLength)

            let target = requestLine[1]
            let path: String
            var query: [String: String] = [:]
            if let qIndex = target.firstIndex(of: "?") {
                path = String(target[..<qIndex])
                let queryString = String(target[target.index(after: qIndex)...])
                for pair in queryString.components(separatedBy: "&") {
                    let parts = pair.components(separatedBy: "=")
                    guard parts.count == 2 else { continue }
                    let key = parts[0].removingPercentEncoding ?? parts[0]
                    let value = parts[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? parts[1]
                    query[key] = value
                }
            } else {
                path = target
            }

            return .request(HarnessHTTPRequest(
                method: requestLine[0],
                path: path,
                query: query,
                headers: headers,
                body: body
            ))
        }
    }

    struct HarnessHTTPResponse {
        let status: Int
        let body: Data

        private static let statusText: [Int: String] = [
            200: "OK", 400: "Bad Request", 401: "Unauthorized",
            404: "Not Found", 500: "Internal Server Error", 504: "Gateway Timeout",
        ]

        func serialized() -> Data {
            let reason = Self.statusText[status] ?? "Unknown"
            var head = "HTTP/1.1 \(status) \(reason)\r\n"
            head += "Content-Type: application/json\r\n"
            head += "Content-Length: \(body.count)\r\n"
            head += "Connection: close\r\n\r\n"
            return Data(head.utf8) + body
        }

        static func json(_ object: Any, status: Int = 200) -> HarnessHTTPResponse {
            let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed]))
                ?? Data(#"{"error":"unencodable response"}"#.utf8)
            return HarnessHTTPResponse(status: status, body: data)
        }

        static func error(_ message: String, status: Int) -> HarnessHTTPResponse {
            json(["error": message], status: status)
        }
    }
#endif
