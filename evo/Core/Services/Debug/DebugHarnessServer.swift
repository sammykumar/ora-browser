#if DEBUG
    import Foundation
    import Network
    import os.log

    /// Debug-only localhost control server. Started from AppDelegate; never present in Release builds.
    final class DebugHarnessServer: @unchecked Sendable {
        static let shared = DebugHarnessServer()

        private static let log = Logger(subsystem: "com.skproductions.evobrowser", category: "DebugHarness")
        private let queue = DispatchQueue(label: "evo.debug-harness")
        private var listener: NWListener?
        private(set) var token: String = ""

        func start() {
            let portValue = UInt16(ProcessInfo.processInfo.environment["EVO_HARNESS_PORT"] ?? "") ?? 4590
            guard let port = NWEndpoint.Port(rawValue: portValue) else {
                Self.log.error("harness: invalid port \(portValue)")
                return
            }

            token = UUID().uuidString
            writeTokenFile()

            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: port)
            parameters.allowLocalEndpointReuse = true

            do {
                let listener = try NWListener(using: parameters)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                listener.stateUpdateHandler = { state in
                    if case let .failed(error) = state {
                        Self.log.error("harness: listener failed \(error.localizedDescription)")
                    }
                }
                listener.start(queue: queue)
                self.listener = listener
                Self.log.info("harness: listening on 127.0.0.1:\(portValue)")
            } catch {
                // The harness must never break normal app launch (port in use, etc.).
                Self.log.error("harness: failed to start \(error.localizedDescription)")
            }
        }

        private func writeTokenFile() {
            let directory = URL.applicationSupportDirectory.appending(path: "Evo")
            let file = directory.appending(path: "harness-token")
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data(token.utf8).write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            } catch {
                Self.log.error("harness: could not write token file \(error.localizedDescription)")
            }
        }

        private func handle(_ connection: NWConnection) {
            connection.start(queue: queue)
            receive(on: connection, accumulated: Data())
        }

        private func receive(on connection: NWConnection, accumulated: Data) {
            connection
                .receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                    guard let self else { return }
                    var buffer = accumulated
                    if let data {
                        buffer.append(data)
                    }
                    if error != nil {
                        connection.cancel()
                        return
                    }
                    switch HarnessHTTPParser.parse(buffer) {
                    case .incomplete:
                        if isComplete {
                            connection.cancel()
                        } else {
                            self.receive(on: connection, accumulated: buffer)
                        }
                    case .invalid:
                        self.send(HarnessHTTPResponse.error("malformed request", status: 400), on: connection)
                    case let .request(request):
                        self.respond(to: request, on: connection)
                    }
                }
        }

        private func respond(to request: HarnessHTTPRequest, on connection: NWConnection) {
            guard request.headers["x-evo-harness-token"] == token else {
                send(HarnessHTTPResponse.error("missing or bad token", status: 401), on: connection)
                return
            }
            Task { @MainActor in
                let response = await DebugHarnessRouter.route(request)
                self.send(response, on: connection)
            }
        }

        private func send(_ response: HarnessHTTPResponse, on connection: NWConnection) {
            connection.send(content: response.serialized(), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
#endif
