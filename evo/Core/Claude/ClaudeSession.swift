//
//  ClaudeSession.swift
//  evo
//
//  Wraps one `claude -p --output-format stream-json` subprocess: writes user
//  turns to its stdin, reads its stdout line-by-line, and surfaces decoded
//  `ClaudeEvent`s as an `AsyncStream`. Binary resolution and MCP config
//  wiring are the job of `ClaudeEngine` (Task 6); this type only knows how
//  to drive an already-resolved binary path.
//

import Foundation

/// Assembles complete newline-terminated lines out of stdout chunks that may
/// split a line across multiple `readabilityHandler` callbacks.
struct LineBuffer {
    private var pending = ""

    mutating func append(_ chunk: String, emit: (String) -> Void) {
        pending += chunk
        while let newlineIndex = pending.firstIndex(of: "\n") {
            emit(String(pending[pending.startIndex ..< newlineIndex]))
            pending = String(pending[pending.index(after: newlineIndex)...])
        }
    }
}

final class ClaudeSession {
    let events: AsyncStream<ClaudeEvent>
    private let process = Process()
    private let stdin = Pipe()
    private var continuation: AsyncStream<ClaudeEvent>.Continuation?

    init(binaryPath: String, workingDirectory: URL, mcpConfigPath: String?) {
        var cont: AsyncStream<ClaudeEvent>.Continuation?
        events = AsyncStream { cont = $0 }
        continuation = cont

        var args = [
            "-p", "--input-format", "stream-json",
            "--output-format", "stream-json", "--verbose"
        ]
        if let mcpConfigPath {
            args += [
                "--mcp-config", mcpConfigPath, "--strict-mcp-config",
                "--permission-mode", "default",
                "--allowedTools", "mcp__evo__read_current_page"
            ]
        }
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        process.currentDirectoryURL = workingDirectory
        process.standardInput = stdin

        let stdout = Pipe()
        process.standardOutput = stdout
        var buffer = LineBuffer()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            buffer.append(chunk) { line in
                if let event = ClaudeStreamEvent.parse(line: line) {
                    self?.continuation?.yield(event)
                }
            }
        }
        process.terminationHandler = { [weak self] proc in
            if proc.terminationStatus != 0 {
                self?.continuation?.yield(.failed("claude exited with code \(proc.terminationStatus)"))
            }
            self?.continuation?.finish()
        }
        do {
            try process.run()
        } catch {
            continuation?.yield(.failed("failed to launch claude: \(error.localizedDescription)"))
            continuation?.finish()
        }
    }

    func send(_ text: String) {
        let payload: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": text]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        stdin.fileHandleForWriting.write(data)
        stdin.fileHandleForWriting.write(Data("\n".utf8))
    }

    func interrupt() {
        process.interrupt()
    }

    func terminate() {
        process.terminate()
        continuation?.finish()
    }
}
