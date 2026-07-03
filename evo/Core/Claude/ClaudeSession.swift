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
/// split a line — or even a single multi-byte UTF-8 codepoint — across
/// multiple `readabilityHandler` callbacks. Buffering happens at the byte
/// level so decoding only ever runs on a complete line.
struct LineBuffer {
    private var pending = Data()

    /// Appends a raw chunk of stdout bytes, emitting each complete
    /// newline-terminated line as it becomes available.
    mutating func append(_ chunk: Data, emit: (String) -> Void) {
        pending.append(chunk)
        while let newlineIndex = pending.firstIndex(of: 0x0A) {
            let lineData = pending[pending.startIndex ..< newlineIndex]
            emitLine(lineData, emit: emit)
            pending.removeSubrange(pending.startIndex ... newlineIndex)
        }
    }

    /// Emits any remaining buffered bytes as a final line. Call this once,
    /// on EOF, to surface a trailing line that never got a newline.
    mutating func flush(emit: (String) -> Void) {
        guard !pending.isEmpty else { return }
        emitLine(pending, emit: emit)
        pending.removeAll()
    }

    private func emitLine(_ lineData: Data, emit: (String) -> Void) {
        var lineData = lineData
        if lineData.last == 0x0D {
            lineData.removeLast()
        }
        // A complete line that still fails to decode as UTF-8 is genuinely
        // malformed (not a chunk-boundary artifact) — skip it.
        if let line = String(data: lineData, encoding: .utf8) {
            emit(line)
        }
    }
}

final class ClaudeSession {
    let events: AsyncStream<ClaudeEvent>
    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    private var continuation: AsyncStream<ClaudeEvent>.Continuation?
    private var lineBuffer = LineBuffer()
    private let mcpConfigPath: String?

    init(binaryPath: String, workingDirectory: URL, mcpConfigPath: String?) {
        var cont: AsyncStream<ClaudeEvent>.Continuation?
        events = AsyncStream { cont = $0 }
        continuation = cont
        self.mcpConfigPath = mcpConfigPath

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

        process.standardOutput = stdout
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF: flush any trailing partial line, then stop polling —
                // otherwise this handler re-arms forever on empty reads.
                self.lineBuffer.flush { line in self.dispatch(line: line) }
                handle.readabilityHandler = nil
                return
            }
            self.lineBuffer.append(data) { line in self.dispatch(line: line) }
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
        stdout.fileHandleForReading.readabilityHandler = nil
        process.terminate()
        continuation?.finish()
        if let mcpConfigPath {
            try? FileManager.default.removeItem(atPath: mcpConfigPath)
        }
    }

    private func dispatch(line: String) {
        if let event = ClaudeStreamEvent.parse(line: line) {
            continuation?.yield(event)
        }
    }
}
