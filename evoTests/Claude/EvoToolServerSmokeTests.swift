//
//  EvoToolServerSmokeTests.swift
//  evoTests
//
//  HARD-GATE spike proof: the real `claude` CLI connects to Evo's in-process MCP
//  server over localhost HTTP and successfully calls the `ping` tool end-to-end.
//
//  This test makes a REAL authenticated `claude` API call — that is expected here.
//  It is gated: if the `claude` binary is not found via a login shell, or if we
//  cannot supply credentials to an isolated `claude` config, the test returns early
//  (passes) so machines without `claude`/auth don't fail the suite.
//
//  Why an isolated CLAUDE_CONFIG_DIR: the developer's global `~/.claude` config
//  loads plugins/skills (e.g. superpowers) that push `claude` into its
//  "tool search" mode, which defers MCP tools behind a ToolSearch step and, in
//  practice, prevents the model from invoking `mcp__evo__ping` directly. Pointing
//  `claude` at a minimal, plugin-free config dir makes the MCP tool directly
//  callable. We replicate the user's OAuth token (or reuse ANTHROPIC_API_KEY) so
//  auth still works in that isolated dir. See task-1-report.md for the full finding.
//

@testable import Evo
import Foundation
import Testing

/// The exact stream-json user line fed to `claude` on stdin (kept at file scope so
/// the literal fits the 120-column limit).
private let pingUserLine = """
{"type":"user","message":{"role":"user","content":"Call the evo ping tool and tell me exactly what it returns."}}
"""

struct EvoToolServerSmokeTests {
    @Test("claude CLI calls the evo ping tool end-to-end")
    func claudeCallsEvoPingTool() async throws {
        // Gate: resolve `claude` via a login shell so PATH matches the user's setup.
        guard let claudePath = resolveClaudeBinary() else {
            // swiftlint:disable:next no_print_statements
            print("[EvoToolServerSmokeTests] `claude` not found on PATH — skipping the round-trip proof.")
            return
        }

        // Prepare an isolated, plugin-free claude config dir with working auth.
        let configDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("evo-claude-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: configDir) }
        guard prepareIsolatedClaudeConfig(at: configDir) else {
            // swiftlint:disable:next no_print_statements
            print("[EvoToolServerSmokeTests] no usable claude credentials to isolate — skipping the round-trip proof.")
            return
        }

        // 1. Start the in-process MCP server on an ephemeral loopback port.
        let url = try await EvoToolServer.shared.start()
        defer { Task { await EvoToolServer.shared.stop() } }

        // 2. Write a temp mcp-config pointing `claude` at our server.
        let mcpConfigURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("evo-mcp-\(UUID().uuidString).json")
        let mcpConfig = """
        { "mcpServers": { "evo": { "type": "http", "url": "\(url.absoluteString)" } } }
        """
        try mcpConfig.write(to: mcpConfigURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: mcpConfigURL) }

        // 3. Spawn `claude` with the exact flags, feeding one stream-json user line.
        let output = try runClaude(
            binary: claudePath,
            configDir: configDir,
            mcpConfigPath: mcpConfigURL.path,
            stdinLine: pingUserLine
        )

        // 4. Assert the round-trip: a tool_use for mcp__evo__ping AND a pong result.
        #expect(
            output.contains("mcp__evo__ping"),
            "expected a tool_use for mcp__evo__ping in claude output:\n\(output)"
        )
        #expect(
            output.contains("tool_result"),
            "expected a tool_result block in claude output:\n\(output)"
        )
        #expect(
            output.contains("pong"),
            "expected the ping tool's `pong` result in claude output:\n\(output)"
        )
    }

    // MARK: - Helpers

    /// Resolves the `claude` binary path through a login shell, or `nil` if absent.
    private func resolveClaudeBinary() -> String? {
        let output = runProcess(
            executable: "/bin/zsh",
            arguments: ["-lc", "which claude"],
            environment: nil
        )
        guard let output, output.status == 0 else { return nil }
        let path = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    /// Populates `configDir` with a minimal `claude` config plus credentials so an
    /// isolated (plugin-free) `claude` invocation can authenticate. Returns `false`
    /// if no usable credentials could be provided.
    private func prepareIsolatedClaudeConfig(at configDir: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            let settings = #"{"hasCompletedOnboarding":true,"theme":"dark"}"#
            try settings.write(
                to: configDir.appendingPathComponent("settings.json"),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            return false
        }

        // If an API key is already in the environment, that alone authenticates.
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
            return true
        }

        // Otherwise replicate the OAuth token from the login keychain into the dir.
        guard let keychain = runProcess(
            executable: "/usr/bin/security",
            arguments: ["find-generic-password", "-s", "Claude Code-credentials", "-w"],
            environment: nil
        ), keychain.status == 0 else {
            return false
        }

        guard
            let data = keychain.stdout.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = json["claudeAiOauth"]
        else {
            return false
        }

        do {
            let credentials = try JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth])
            let credentialsURL = configDir.appendingPathComponent(".credentials.json")
            try credentials.write(to: credentialsURL)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: credentialsURL.path
            )
            return true
        } catch {
            return false
        }
    }

    /// Runs `claude` with the exact spike flags against an isolated config dir,
    /// writes one stream-json line to stdin, and returns its captured stdout.
    private func runClaude(
        binary: String,
        configDir: URL,
        mcpConfigPath: String,
        stdinLine: String
    ) throws -> String {
        // Isolate from the parent Claude Code session: strip nested-session markers
        // and pin the plugin-free config dir.
        var environment = ProcessInfo.processInfo.environment
        for key in environment.keys where key == "CLAUDECODE"
            || key == "AI_AGENT" || key == "CLAUDE_EFFORT" || key.hasPrefix("CLAUDE_CODE")
        {
            environment.removeValue(forKey: key)
        }
        environment["CLAUDE_CONFIG_DIR"] = configDir.path

        let output = runProcess(
            executable: binary,
            arguments: [
                "-p",
                "--input-format", "stream-json",
                "--output-format", "stream-json",
                "--verbose",
                "--mcp-config", mcpConfigPath,
                "--strict-mcp-config",
                "--permission-mode", "default",
                "--allowedTools", "mcp__evo__ping"
            ],
            environment: environment,
            stdin: stdinLine + "\n",
            timeout: 180
        )
        return output?.stdout ?? ""
    }

    private struct ProcessOutput {
        let status: Int32
        let stdout: String
    }

    /// Runs a subprocess, optionally writing `stdin`, and captures stdout. Terminates
    /// after `timeout` seconds. Returns `nil` if the process could not be launched.
    private func runProcess(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        stdin: String? = nil,
        timeout: TimeInterval = 30
    ) -> ProcessOutput? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        let stdinPipe = Pipe()
        if stdin != nil { process.standardInput = stdinPipe }

        do {
            try process.run()
        } catch {
            return nil
        }

        let timeoutItem = DispatchWorkItem { [weak process] in
            if process?.isRunning == true { process?.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

        if let stdin, let data = stdin.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        if stdin != nil { try? stdinPipe.fileHandleForWriting.close() }

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeoutItem.cancel()

        let stdout = String(bytes: outData, encoding: .utf8) ?? ""
        return ProcessOutput(status: process.terminationStatus, stdout: stdout)
    }
}
