//
//  OpHelperProcess.swift
//  evo
//
//  Swift-side client for the `evo-op-helper` Go sidecar. Speaks NDJSON over
//  stdin/stdout, correlating responses to requests by id. The real subprocess
//  transport (`ProcessOpHelperTransport`) is behind the `OpHelperTransport`
//  seam so `OpHelperProcess` itself can be unit-tested without spawning a
//  real process.
//

import Foundation
import os

enum OpHelperError: Error, Equatable {
    case timeout
    case notRunning
    case wire(code: String, message: String)
    case decode
}

/// Abstracts the byte transport so tests can drive request/response without a real process.
protocol OpHelperTransport: AnyObject {
    var onLine: ((String) -> Void)? { get set }
    func send(line: String) throws
    func terminate()
}

/// One subprocess bound to ONE 1Password account. NDJSON request/response with id correlation.
actor OpHelperProcess {
    private let transport: OpHelperTransport
    private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var counter: UInt64 = 0
    private let requestTimeout: TimeInterval
    private let logger = Logger(subsystem: "com.skproductions.evobrowser", category: "op-helper")

    init(transport: OpHelperTransport, requestTimeout: TimeInterval = 25) {
        self.transport = transport
        self.requestTimeout = requestTimeout
        transport.onLine = { [weak self] line in
            Task { await self?.receive(line: line) }
        }
    }

    func request(method: String, params: [String: Any]) async throws -> [String: Any] {
        counter += 1
        let id = "\(counter)"
        var payload: [String: Any] = ["id": id, "method": method]
        if !params.isEmpty { payload["params"] = params }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: data, encoding: .utf8)
        else {
            throw OpHelperError.decode
        }

        return try await withThrowingTaskGroup(of: [String: Any].self) { group in
            group.addTask { try await self.awaitResponse(id: id, line: line) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.requestTimeout * 1_000_000_000))
                throw OpHelperError.timeout
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw OpHelperError.timeout }
            return first
        }
    }

    private func awaitResponse(id: String, line: String) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try transport.send(line: line)
            } catch {
                pending[id] = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func receive(line: String) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? String,
              let continuation = pending.removeValue(forKey: id)
        else {
            return
        }
        // swiftlint:disable:next identifier_name
        if let ok = obj["ok"] as? Bool, ok {
            continuation.resume(returning: obj["result"] as? [String: Any] ?? [:])
        } else if let err = obj["error"] as? [String: Any] {
            continuation.resume(throwing: OpHelperError.wire(
                code: err["code"] as? String ?? "internal",
                message: err["message"] as? String ?? ""
            ))
        } else {
            continuation.resume(throwing: OpHelperError.decode)
        }
    }

    func shutdown() {
        transport.terminate()
        for (_, continuation) in pending {
            continuation.resume(throwing: OpHelperError.notRunning)
        }
        pending.removeAll()
    }

    nonisolated func shutdownSync() {
        Task { await shutdown() }
    }
}

/// Real transport: spawns `evo-op-helper --account <name>` and frames stdout with LineBuffer.
final class ProcessOpHelperTransport: OpHelperTransport {
    var onLine: ((String) -> Void)?
    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    private var lineBuffer = LineBuffer()

    init(binaryURL: URL, accountName: String, integrationVersion: String) {
        process.executableURL = binaryURL
        process.arguments = [
            "--account", accountName,
            "--integration-name", "Evo",
            "--integration-version", integrationVersion
        ]
        process.standardInput = stdin
        process.standardOutput = stdout
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty else {
                self.lineBuffer.flush { self.onLine?($0) }
                handle.readabilityHandler = nil
                return
            }
            self.lineBuffer.append(data) { self.onLine?($0) }
        }
    }

    func start() throws {
        try process.run()
    }

    func send(line: String) throws {
        try stdin.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
    }

    func terminate() {
        stdout.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }
}
