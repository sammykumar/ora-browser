//
//  EvoToolServer.swift
//  Evo
//
//  Transport decision — PATH B (SDK server transport is framework-agnostic; we
//  supply the socket ourselves, but delegate MCP semantics to the SDK).
//
//  The Swift MCP SDK (modelcontextprotocol/swift-sdk, resolved 0.12.1) DOES ship
//  HTTP *server* transports — `StatelessHTTPServerTransport` /
//  `StatefulHTTPServerTransport` under Sources/MCP/Base/Transports/HTTPServer/.
//  BUT they are deliberately framework-agnostic: each exposes
//  `handleRequest(HTTPRequest) async -> HTTPResponse` and never opens a socket.
//  The SDK's own conformance server binds the port with swift-nio (see
//  Sources/MCPConformance/Server/HTTPApp.swift), and swift-nio is NOT part of the
//  `MCP` library product. So there is no ready-to-use listening server transport
//  we can hand to `server.start(transport:)` and have it accept TCP connections.
//
//  Therefore this is Path B: we provide the network listener ourselves via
//  Network.framework (`NWListener`, loopback-only, ephemeral port) and forward each
//  parsed HTTP request into the SDK's `StatelessHTTPServerTransport`, which does all
//  the MCP Streamable HTTP work — JSON-RPC routing, the initialize handshake, and
//  request validation. We only implement a minimal HTTP/1.1 request parser and
//  response writer (~one file), not the MCP protocol itself.
//
//  Stateless mode (single JSON responses, no SSE, no session id) is sufficient for
//  the `read_current_page` round-trip. The `claude` CLI's Streamable HTTP client
//  sends `Accept: application/json, text/event-stream`; the stateless `.jsonOnly`
//  Accept validator accepts that (it only requires `application/json` to be
//  present).
//

import Foundation
import MCP
import Network

/// In-process MCP server that exposes the `read_current_page` tool over localhost
/// HTTP, for the `claude` CLI to connect to via `--mcp-config`.
actor EvoToolServer {
    static let shared = EvoToolServer()

    private var server: Server?
    private var transport: StatelessHTTPServerTransport?
    private var listener: NWListener?
    private(set) var endpoint: URL?

    private let queue = DispatchQueue(label: "com.skproductions.evo.mcp.listener")

    /// Starts the server (idempotent) and returns the MCP endpoint URL, e.g.
    /// `http://127.0.0.1:<port>/mcp`.
    func start() async throws -> URL {
        if let endpoint { return endpoint }

        let transport = StatelessHTTPServerTransport()
        let server = Server(
            name: "evo",
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            // inputSchema MUST be a valid JSON-Schema object (`{"type":"object",…}`).
            // An empty `{}` is rejected by some MCP clients (incl. `claude`), which
            // then silently drop the tool — so spell out the object schema.
            let schema: Value = .object([
                "type": .string("object"),
                "properties": .object([:])
            ])
            return ListTools.Result(tools: [
                Tool(
                    name: "read_current_page",
                    description: "Reads the visible text of the browser's current active tab",
                    inputSchema: schema
                )
            ])
        }
        await server.withMethodHandler(CallTool.self) { params in
            guard params.name == "read_current_page" else {
                return CallTool.Result(content: [.text("unknown tool")], isError: true)
            }
            let provider = await MainActor.run { FrontmostTabRegistry.shared.provider }
            let out = await ReadCurrentPageTool.run(provider: provider)
            return CallTool.Result(content: [.text(out.text)], isError: out.isError)
        }

        try await server.start(transport: transport)

        let port = try await startListener(transport: transport)

        guard let url = URL(string: "http://127.0.0.1:\(port)/mcp") else {
            throw MCPError.internalError("Could not form MCP endpoint URL")
        }

        self.transport = transport
        self.server = server
        endpoint = url
        return url
    }

    /// Tears the server and listener down.
    func stop() async {
        listener?.cancel()
        listener = nil
        await server?.stop()
        await transport?.disconnect()
        server = nil
        transport = nil
        endpoint = nil
    }

    // MARK: - Network.framework listener

    /// Binds a loopback-only listener on an ephemeral port and returns the port.
    private func startListener(transport: StatelessHTTPServerTransport) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters)
        self.listener = listener

        let queue = queue
        listener.newConnectionHandler = { connection in
            Self.handleConnection(connection, transport: transport, queue: queue)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let resumer = ContinuationResumer(continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port {
                        resumer.resume(returning: port.rawValue)
                    } else {
                        resumer.resume(throwing: MCPError.internalError("Listener ready without a port"))
                    }
                case let .failed(error):
                    resumer.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    // MARK: - Per-connection HTTP/1.1 handling

    private static func handleConnection(
        _ connection: NWConnection,
        transport: StatelessHTTPServerTransport,
        queue: DispatchQueue
    ) {
        connection.start(queue: queue)
        receive(connection, transport: transport, buffer: Data())
    }

    /// Recursively accumulates bytes until a full HTTP request is parsed, forwards it
    /// to the MCP transport, writes the response, and closes the connection.
    private static func receive(
        _ connection: NWConnection,
        transport: StatelessHTTPServerTransport,
        buffer: Data
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }

            if let request = parseRequest(buffer) {
                Task {
                    let response = await transport.handleRequest(request)
                    let raw = serializeResponse(response)
                    connection.send(content: raw, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
                return
            }

            if isComplete || error != nil {
                connection.cancel()
                return
            }

            receive(connection, transport: transport, buffer: buffer)
        }
    }

    /// Parses a complete HTTP/1.1 request from `buffer`, or returns `nil` if more
    /// bytes are needed.
    private static func parseRequest(_ buffer: Data) -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = buffer.range(of: separator) else { return nil }

        let headerData = buffer[buffer.startIndex ..< headerRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        var lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else { return nil }
        let method = String(requestParts[0])
        let path = String(requestParts[1])
        lines.removeFirst()

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[line.startIndex ..< colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { headers[name] = value }
        }

        let contentLength = headers
            .first { $0.key.lowercased() == "content-length" }
            .flatMap { Int($0.value) } ?? 0

        let bodyStart = headerRange.upperBound
        let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
        if available < contentLength { return nil }

        let body: Data?
        if contentLength > 0 {
            let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
            body = Data(buffer[bodyStart ..< bodyEnd])
        } else {
            body = nil
        }

        return HTTPRequest(method: method, headers: headers, body: body, path: path)
    }

    /// Serializes an SDK `HTTPResponse` into a raw HTTP/1.1 response, forcing
    /// `Connection: close` so each client request maps to one connection.
    private static func serializeResponse(_ response: HTTPResponse) -> Data {
        let status = response.statusCode
        let body = response.bodyData ?? Data()

        var headers = response.headers
        headers["Content-Length"] = String(body.count)
        headers["Connection"] = "close"

        var head = "HTTP/1.1 \(status) \(reasonPhrase(status))\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"

        var out = Data(head.utf8)
        out.append(body)
        return out
    }

    private static func reasonPhrase(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 406: "Not Acceptable"
        case 415: "Unsupported Media Type"
        case 500: "Internal Server Error"
        default: status < 400 ? "OK" : "Error"
        }
    }
}

/// One-shot wrapper so a `CheckedContinuation` can be resumed from a callback that
/// may fire multiple times (only the first resume takes effect).
private final class ContinuationResumer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UInt16, Error>?

    init(_ continuation: CheckedContinuation<UInt16, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: UInt16) {
        lock.lock()
        defer { lock.unlock() }
        continuation?.resume(returning: value)
        continuation = nil
    }

    func resume(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
