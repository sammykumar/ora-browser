# Claude Side Panel (Walking Skeleton) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a read-only Claude side panel in Evo where the user types a prompt, a real `claude` CLI subprocess runs, and Claude can read the page in the frontmost tab through an MCP tool Evo serves over its own authenticated WebView.

**Architecture:** An app-wide `ClaudeEngine` singleton spawns the `claude` CLI in `stream-json` mode (one `Process` per session) and parses its stdout into typed events surfaced as an `AsyncStream`. An app-wide `EvoToolServer` singleton runs an in-process MCP server on `127.0.0.1:<ephemeral-port>` exposing one tool, `read_current_page`, backed by the frontmost window's active `WKWebView`. A per-window `ClaudeChatManager` (`@MainActor ObservableObject`) bridges engine events to `@Published` state rendered by `ClaudeSidePanelView`, docked via a nested `HSplit` inside the existing browser content pane.

**Tech Stack:** Swift 6.3 / SwiftUI, macOS 15.0 target, `Foundation.Process`, `AsyncStream`, `WKWebView.evaluateJavaScript`, the vendored `HSplit`, Swift MCP SDK (`modelcontextprotocol/swift-sdk`), Swift Testing (`import Testing`). XcodeGen (`project.yml` → `xcodegen`).

## Global Constraints

- **Module name is `Evo`; tests `@testable import Evo`.** Internal type prefix in new code: no `Ora`/`Evo` prefix needed on new types (use plain names like `ClaudeEngine`).
- **Target the DEBUG build only** (`evo-debug.entitlements`, un-sandboxed). The debug build spawns subprocesses; the sandboxed release cannot. Do not attempt a release/sandbox path in this plan.
- **macOS deploymentTarget: 15.0.** Swift version 6.3.3.
- **Style:** SwiftFormat 4-space indent, 120-col, `--self remove`. SwiftLint bans `force_unwrapping` and `implicitly_unwrapped_optional` in new code. Run `swiftformat .` and `swiftlint lint --fix --use-alternative-excluding` before each commit.
- **Concurrency style:** per-window UI state is `@MainActor final class …: ObservableObject` with `@Published`; cross-window services are `static let shared` singletons. No Combine pipelines — `async/await`, `Task`, `AsyncStream`.
- **After any `project.yml` change, run `xcodegen`** before building. Build with `./scripts/xcbuild-debug.sh`.
- **`claude` CLI invocation (verbatim):** `claude -p --input-format stream-json --output-format stream-json --verbose --mcp-config <path> --strict-mcp-config --permission-mode default --allowedTools mcp__evo__read_current_page`
- **`claude` binary is at a non-stable fnm path** — never hardcode it; resolve at runtime (Task 4) with a Settings override.

---

## File Structure

**New files:**
- `evo/Core/Claude/ClaudeStreamEvent.swift` — `Codable` model + decoder for one `stream-json` stdout line. (Task 2)
- `evo/Core/Claude/ClaudeEvent.swift` — the reduced app-facing event enum the UI consumes. (Task 2)
- `evo/Core/Claude/ClaudeBinaryLocator.swift` — resolves the `claude` path (override → login-shell `which`). (Task 4)
- `evo/Core/Claude/ClaudeSession.swift` — one `Process` + its stdin/stdout plumbing + `AsyncStream`. (Task 3)
- `evo/Core/Claude/ClaudeEngine.swift` — `static let shared`; owns sessions, writes `--mcp-config`. (Task 3, Task 5)
- `evo/Core/Claude/MCP/EvoToolServer.swift` — in-process MCP server on localhost. (Task 1, Task 6)
- `evo/Core/Claude/MCP/ActiveTabTextProvider.swift` — protocol + live impl reading `innerText`. (Task 6)
- `evo/Features/Claude/State/ClaudeChatManager.swift` — per-window `ObservableObject`. (Task 7)
- `evo/Features/Claude/State/ClaudePanelManager.swift` — panel visibility/width, mirrors `SidebarManager`. (Task 8)
- `evo/Features/Claude/Views/ClaudeSidePanelView.swift` — the panel UI. (Task 8)
- `evo/Features/Claude/Views/ClaudeMessageRow.swift` — one message / tool-call row. (Task 8)
- `evoTests/Claude/ClaudeStreamEventTests.swift` — parser tests. (Task 2)
- `evoTests/Claude/ReadCurrentPageToolTests.swift` — tool handler tests. (Task 6)
- `evoTests/Claude/Fixtures/` — captured `stream-json` lines. (Task 2)

**Modified files:**
- `project.yml` — add the `swift-sdk` package + target dep. (Task 1)
- `evo/App/EvoRoot.swift:35-103` — construct + inject `ClaudeChatManager` and `ClaudePanelManager`. (Task 8)
- `evo/Features/Browser/Views/BrowserSplitView.swift:78-91` — nest the Claude panel `HSplit` in `contentView()`. (Task 8)
- `evo/Features/Settings/SettingsContentView.swift:4-103` — add a "Claude" settings section. (Task 9)
- `evo/Features/Settings/Sections/` — new `ClaudeSettingsView.swift`. (Task 9)

---

## Task 1: Spike — prove an in-process MCP server that the real `claude` CLI calls

**This task is an exploratory spike, not TDD.** Its deliverable is a *decision* plus a *working proof*: a localhost MCP server exposing a trivial `ping` tool that the real `claude` binary invokes end-to-end. It resolves the plan's one open risk (does the Swift MCP SDK ship a usable HTTP **server** transport?) before any real feature code depends on it.

**Files:**
- Modify: `project.yml` (packages + target deps)
- Create: `evo/Core/Claude/MCP/EvoToolServer.swift` (minimal `ping`-only version)
- Create: `scripts/spike-mcp-smoke.sh` (throwaway harness; delete at task end)

**Interfaces:**
- Produces: `actor EvoToolServer { static let shared: EvoToolServer; func start() async throws -> URL /* the MCP endpoint, e.g. http://127.0.0.1:<port>/mcp */; func stop() async }`. Later tasks assume `start()` returns the endpoint `URL` and that a `--mcp-config` pointing at it works.

- [ ] **Step 1: Add the Swift MCP SDK dependency**

In `project.yml`, under `packages:` add:

```yaml
  MCP:
    url: https://github.com/modelcontextprotocol/swift-sdk
    from: 0.9.0
```

And under the `Evo` target `dependencies:` (next to `Sparkle`, `Inject`, …) add:

```yaml
      - package: MCP
        product: MCP
```

Then run:

```bash
xcodegen && ./scripts/xcbuild-debug.sh
```

Expected: build succeeds with the new package resolved. If `0.9.0` does not resolve, run `git ls-remote --tags https://github.com/modelcontextprotocol/swift-sdk` and pin the latest published tag.

- [ ] **Step 2: Determine the server transport the SDK offers**

Inspect the resolved package sources under `~/Library/Developer/Xcode/DerivedData/Evo-*/SourcePackages/checkouts/swift-sdk/Sources/`. Grep for a server-side network transport:

```bash
grep -rniE "server|transport|http|listen|niohttp|network" \
  ~/Library/Developer/Xcode/DerivedData/Evo-*/SourcePackages/checkouts/swift-sdk/Sources/ \
  | grep -iE "transport|server" | head -40
```

Record the answer in a comment at the top of `EvoToolServer.swift`:
- **Path A** — the SDK exposes an HTTP/SSE **server** transport → use it.
- **Path B** — the SDK only has stdio + HTTP **client** → implement a minimal MCP **Streamable HTTP** server on `Network.framework` (`NWListener`) that hands the SDK `Server` a custom `Transport`, or handles the JSON-RPC POST/SSE directly. Keep it ~100 lines, one file.

- [ ] **Step 3: Write `EvoToolServer` with a single `ping` tool**

Using whichever path Step 2 chose, implement `EvoToolServer` as an `actor` that binds `127.0.0.1` on an ephemeral port, serves MCP, and exposes one tool named `ping` that returns text `"pong"`. Sketch (adjust to the confirmed SDK API):

```swift
import Foundation
import MCP

actor EvoToolServer {
    static let shared = EvoToolServer()

    private var server: Server?
    private(set) var endpoint: URL?

    func start() async throws -> URL {
        if let endpoint { return endpoint }
        let server = Server(
            name: "evo",
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: false))
        )
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: [Tool(name: "ping", description: "Returns pong", inputSchema: .object([:]))])
        }
        await server.withMethodHandler(CallTool.self) { params in
            guard params.name == "ping" else {
                return .init(content: [.text("unknown tool")], isError: true)
            }
            return .init(content: [.text("pong")], isError: false)
        }
        // Path A: try await server.start(transport: httpServerTransport(port: 0))
        // Path B: bind NWListener, wire a custom Transport, then server.start(transport:)
        let url = /* the bound endpoint, e.g. */ URL(string: "http://127.0.0.1:\(boundPort)/mcp")! // swiftlint:disable:this force_unwrapping
        self.server = server
        self.endpoint = url
        return url
    }

    func stop() async { await server?.stop(); server = nil; endpoint = nil }
}
```

- [ ] **Step 4: Prove the real `claude` CLI calls it**

Add a temporary Debug-only call in `AppDelegate.applicationDidFinishLaunching` that runs `let url = try await EvoToolServer.shared.start()` and logs the URL. Build & launch:

```bash
./scripts/xcbuild-debug.sh && open ~/Library/Developer/Xcode/DerivedData/Evo-*/Build/Products/Debug/Evo.app
```

Copy the logged URL. Then in `scripts/spike-mcp-smoke.sh`, write an mcp-config and invoke `claude` against it:

```bash
#!/bin/zsh
set -euo pipefail
URL="$1"   # e.g. http://127.0.0.1:52731/mcp
CFG=$(mktemp -t evo-mcp).json
cat > "$CFG" <<JSON
{ "mcpServers": { "evo": { "type": "http", "url": "$URL" } } }
JSON
echo '{"type":"user","message":{"role":"user","content":"Call the evo ping tool and tell me exactly what it returns."}}' \
 | claude -p --input-format stream-json --output-format stream-json --verbose \
     --mcp-config "$CFG" --strict-mcp-config --permission-mode default \
     --allowedTools mcp__evo__ping
```

Run: `zsh scripts/spike-mcp-smoke.sh <logged-url>`
Expected: the stream-json output contains a `tool_use` for `mcp__evo__ping` and a `tool_result` with `pong`.

- [ ] **Step 5: Record the decision, remove the throwaway harness, commit**

Delete `scripts/spike-mcp-smoke.sh` and the temporary `AppDelegate` call. Leave the Path-A/Path-B decision comment in `EvoToolServer.swift`.

```bash
swiftformat . && swiftlint lint --fix --use-alternative-excluding
git add project.yml evo/Core/Claude/MCP/EvoToolServer.swift
git commit -m "feat(claude): in-process MCP server spike — claude CLI calls evo ping tool"
```

Expected: clean commit. **Gate:** do not proceed until the `pong` round-trip is proven.

---

## Task 2: `stream-json` event parser

**Files:**
- Create: `evo/Core/Claude/ClaudeStreamEvent.swift`
- Create: `evo/Core/Claude/ClaudeEvent.swift`
- Create: `evoTests/Claude/ClaudeStreamEventTests.swift`
- Create: `evoTests/Claude/Fixtures/*.jsonl`

**Interfaces:**
- Produces: `enum ClaudeEvent: Equatable { case sessionStarted(id: String); case assistantText(String); case toolUse(name: String, id: String); case toolResult(id: String, text: String, isError: Bool); case result(usageUSD: Double?); case failed(String) }`
- Produces: `enum ClaudeStreamEvent { static func parse(line: String) -> ClaudeEvent? }` — returns `nil` for blank/unrecognized/malformed lines (never throws).

- [ ] **Step 1: Capture real fixtures**

Run the real CLI once and save its output as the source of truth:

```bash
echo '{"type":"user","message":{"role":"user","content":"say hello in one word"}}' \
 | claude -p --input-format stream-json --output-format stream-json --verbose \
 > evoTests/Claude/Fixtures/hello.jsonl
```

Open `hello.jsonl` and confirm it contains lines with `"type":"system"` (with `session_id`), `"type":"assistant"` (with `message.content[].text`), and `"type":"result"` (with `total_cost_usd` or similar). Note the exact key names — the decoder in Step 3 must match them.

- [ ] **Step 2: Write the failing tests**

```swift
import Testing
@testable import Evo

struct ClaudeStreamEventTests {
    @Test func parsesSessionInit() {
        let line = #"{"type":"system","subtype":"init","session_id":"abc-123"}"#
        #expect(ClaudeStreamEvent.parse(line: line) == .sessionStarted(id: "abc-123"))
    }

    @Test func parsesAssistantText() {
        let line = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hello"}]}}"#
        #expect(ClaudeStreamEvent.parse(line: line) == .assistantText("Hello"))
    }

    @Test func parsesToolUse() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_1","name":"mcp__evo__read_current_page","input":{}}]}}"#
        #expect(ClaudeStreamEvent.parse(line: line) == .toolUse(name: "mcp__evo__read_current_page", id: "tu_1"))
    }

    @Test func parsesResultWithCost() {
        let line = #"{"type":"result","subtype":"success","total_cost_usd":0.0123}"#
        #expect(ClaudeStreamEvent.parse(line: line) == .result(usageUSD: 0.0123))
    }

    @Test func ignoresBlankAndGarbage() {
        #expect(ClaudeStreamEvent.parse(line: "") == nil)
        #expect(ClaudeStreamEvent.parse(line: "not json") == nil)
        #expect(ClaudeStreamEvent.parse(line: #"{"type":"unknown_kind"}"#) == nil)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  -only-testing:evoTests/ClaudeStreamEventTests
```
Expected: FAIL — `ClaudeStreamEvent` / `ClaudeEvent` undefined.

- [ ] **Step 4: Implement the model + parser**

```swift
import Foundation

enum ClaudeEvent: Equatable {
    case sessionStarted(id: String)
    case assistantText(String)
    case toolUse(name: String, id: String)
    case toolResult(id: String, text: String, isError: Bool)
    case result(usageUSD: Double?)
    case failed(String)
}

enum ClaudeStreamEvent {
    static func parse(line: String) -> ClaudeEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return nil }

        switch type {
        case "system":
            if let id = obj["session_id"] as? String { return .sessionStarted(id: id) }
            return nil
        case "assistant":
            guard let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return nil }
            for part in content {
                switch part["type"] as? String {
                case "text": if let t = part["text"] as? String { return .assistantText(t) }
                case "tool_use":
                    if let name = part["name"] as? String, let id = part["id"] as? String {
                        return .toolUse(name: name, id: id)
                    }
                default: continue
                }
            }
            return nil
        case "result":
            return .result(usageUSD: obj["total_cost_usd"] as? Double)
        default:
            return nil
        }
    }
}
```

Note: if Step 1's fixtures show different key names (e.g. `cost_usd`), update the string literals here and in the tests to match the captured reality.

- [ ] **Step 5: Run tests to verify they pass**

Run the same `xcodebuild test -only-testing:evoTests/ClaudeStreamEventTests` command.
Expected: PASS (all 5 tests).

- [ ] **Step 6: Commit**

```bash
swiftformat . && swiftlint lint --fix --use-alternative-excluding
git add evo/Core/Claude/ClaudeStreamEvent.swift evo/Core/Claude/ClaudeEvent.swift evoTests/Claude/
git commit -m "feat(claude): stream-json event parser with fixtures"
```

---

## Task 3: `ClaudeSession` — one subprocess, stdin in, events out

**Files:**
- Create: `evo/Core/Claude/ClaudeSession.swift`
- Create: `evo/Core/Claude/ClaudeEngine.swift` (session-owning shell; MCP wiring added in Task 6)

**Interfaces:**
- Consumes: `ClaudeEvent` / `ClaudeStreamEvent.parse` (Task 2).
- Produces: `final class ClaudeSession { init(binaryPath: String, workingDirectory: URL, mcpConfigPath: String?); var events: AsyncStream<ClaudeEvent> { get }; func send(_ text: String); func interrupt(); func terminate() }`
- Produces: `final class ClaudeEngine { static let shared: ClaudeEngine; func makeSession(workingDirectory: URL) throws -> ClaudeSession }` (binary + mcp-config resolution filled in Tasks 4 & 6).

- [ ] **Step 1: Write the failing test (line-buffering of split stdout)**

The only pure-logic seam worth unit-testing here is stdout line assembly (bytes can arrive split across reads). Extract it to a testable helper.

```swift
import Testing
@testable import Evo

struct LineBufferTests {
    @Test func emitsCompleteLinesAcrossChunks() {
        var out: [String] = []
        var buf = LineBuffer()
        buf.append("{\"a\":1}\n{\"b\"", emit: { out.append($0) })
        buf.append(":2}\n", emit: { out.append($0) })
        #expect(out == ["{\"a\":1}", "{\"b\":2}"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -only-testing:evoTests/LineBufferTests
```
Expected: FAIL — `LineBuffer` undefined.

- [ ] **Step 3: Implement `LineBuffer` + `ClaudeSession`**

```swift
// LineBuffer.swift content lives in ClaudeSession.swift
struct LineBuffer {
    private var pending = ""
    mutating func append(_ chunk: String, emit: (String) -> Void) {
        pending += chunk
        while let nl = pending.firstIndex(of: "\n") {
            emit(String(pending[pending.startIndex..<nl]))
            pending = String(pending[pending.index(after: nl)...])
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

        var args = ["-p", "--input-format", "stream-json",
                    "--output-format", "stream-json", "--verbose"]
        if let mcpConfigPath {
            args += ["--mcp-config", mcpConfigPath, "--strict-mcp-config",
                     "--permission-mode", "default",
                     "--allowedTools", "mcp__evo__read_current_page"]
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
        do { try process.run() }
        catch { continuation?.yield(.failed("failed to launch claude: \(error.localizedDescription)")); continuation?.finish() }
    }

    func send(_ text: String) {
        let payload: [String: Any] = ["type": "user",
            "message": ["role": "user", "content": text]]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        stdin.fileHandleForWriting.write(data)
        stdin.fileHandleForWriting.write(Data("\n".utf8))
    }

    func interrupt() { process.interrupt() }
    func terminate() { process.terminate(); continuation?.finish() }
}

final class ClaudeEngine {
    static let shared = ClaudeEngine()
    private init() {}
    // makeSession(workingDirectory:) is completed in Task 6 (binary + mcp-config).
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the `-only-testing:evoTests/LineBufferTests` command.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
swiftformat . && swiftlint lint --fix --use-alternative-excluding
git add evo/Core/Claude/ClaudeSession.swift evo/Core/Claude/ClaudeEngine.swift evoTests/Claude/
git commit -m "feat(claude): ClaudeSession subprocess with line-buffered event stream"
```

---

## Task 4: `ClaudeBinaryLocator` — resolve the non-stable `claude` path

**Files:**
- Create: `evo/Core/Claude/ClaudeBinaryLocator.swift`
- Create: `evoTests/Claude/ClaudeBinaryLocatorTests.swift`

**Interfaces:**
- Produces: `enum ClaudeBinaryLocator { static func resolve(override: String?, runWhich: () -> String?) -> Result<String, LocatorError>; enum LocatorError: Error, Equatable { case notFound } }`
- Produces (live convenience): `static func resolve() -> Result<String, LocatorError>` — reads override from `UserDefaults.standard.string(forKey: "claude.binaryPath")`, else runs a login shell `which`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import Evo

struct ClaudeBinaryLocatorTests {
    @Test func prefersValidOverride() {
        let r = ClaudeBinaryLocator.resolve(override: "/opt/claude", runWhich: { nil })
        #expect(r == .success("/opt/claude"))
    }
    @Test func fallsBackToWhich() {
        let r = ClaudeBinaryLocator.resolve(override: nil, runWhich: { "/usr/local/bin/claude" })
        #expect(r == .success("/usr/local/bin/claude"))
    }
    @Test func ignoresBlankOverride() {
        let r = ClaudeBinaryLocator.resolve(override: "   ", runWhich: { "/x/claude" })
        #expect(r == .success("/x/claude"))
    }
    @Test func failsWhenNothingFound() {
        let r = ClaudeBinaryLocator.resolve(override: nil, runWhich: { nil })
        #expect(r == .failure(.notFound))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -only-testing:evoTests/ClaudeBinaryLocatorTests
```
Expected: FAIL — `ClaudeBinaryLocator` undefined.

- [ ] **Step 3: Implement the locator**

```swift
import Foundation

enum ClaudeBinaryLocator {
    enum LocatorError: Error, Equatable { case notFound }

    static func resolve(override: String?, runWhich: () -> String?) -> Result<String, LocatorError> {
        if let override, !override.trimmingCharacters(in: .whitespaces).isEmpty {
            return .success(override)
        }
        if let found = runWhich(), !found.isEmpty { return .success(found) }
        return .failure(.notFound)
    }

    static func resolve() -> Result<String, LocatorError> {
        resolve(
            override: UserDefaults.standard.string(forKey: "claude.binaryPath"),
            runWhich: {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-lc", "which claude"]
                let out = Pipe(); p.standardOutput = out
                try? p.run(); p.waitUntilExit()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (s?.isEmpty == false) ? s : nil
            }
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the `-only-testing:evoTests/ClaudeBinaryLocatorTests` command.
Expected: PASS (all 4).

- [ ] **Step 5: Commit**

```bash
swiftformat . && swiftlint lint --fix --use-alternative-excluding
git add evo/Core/Claude/ClaudeBinaryLocator.swift evoTests/Claude/ClaudeBinaryLocatorTests.swift
git commit -m "feat(claude): resolve claude binary via override or login-shell which"
```

---

## Task 5: Frontmost-window tracking for "current page"

**Files:**
- Create: `evo/Core/Claude/MCP/ActiveTabTextProvider.swift`
- Modify: `evo/App/EvoRoot.swift:78-103` (register the window's `TabManager` as frontmost on appear/focus)

**Interfaces:**
- Produces: `protocol ActiveTabTextProvider: AnyObject { func currentPageText() async -> Result<String, PageReadError> }` and `enum PageReadError: Error, Equatable { case noActiveTab; case evalFailed(String) }`
- Produces: `@MainActor final class FrontmostTabRegistry { static let shared: FrontmostTabRegistry; func setFrontmost(_ provider: ActiveTabTextProvider?); var provider: ActiveTabTextProvider? }`
- Produces: `@MainActor final class LiveActiveTabTextProvider: ActiveTabTextProvider { init(tabManager: TabManager) }` — reads `tabManager.activeTab` and evaluates `document.body.innerText`.

- [ ] **Step 1: Implement the registry + live provider**

```swift
import Foundation

enum PageReadError: Error, Equatable { case noActiveTab; case evalFailed(String) }

protocol ActiveTabTextProvider: AnyObject {
    func currentPageText() async -> Result<String, PageReadError>
}

@MainActor final class FrontmostTabRegistry {
    static let shared = FrontmostTabRegistry()
    private init() {}
    private(set) weak var provider: ActiveTabTextProvider?
    func setFrontmost(_ provider: ActiveTabTextProvider?) { self.provider = provider }
}

@MainActor final class LiveActiveTabTextProvider: ActiveTabTextProvider {
    private let tabManager: TabManager
    init(tabManager: TabManager) { self.tabManager = tabManager }

    func currentPageText() async -> Result<String, PageReadError> {
        guard let tab = tabManager.activeTab else { return .failure(.noActiveTab) }
        return await withCheckedContinuation { cont in
            tab.evaluateJavaScript("document.body.innerText") { value, error in
                if let error { cont.resume(returning: .failure(.evalFailed(error.localizedDescription))) }
                else { cont.resume(returning: .success((value as? String) ?? "")) }
            }
        }
    }
}
```

- [ ] **Step 2: Register the frontmost provider from `EvoRoot`**

In `EvoRoot.swift`, hold a `LiveActiveTabTextProvider` built from the window's `tabManager`, and register it when the window appears/gains focus. In `body`'s `.onAppear` (near `EvoRoot.swift:104`) and on window-focus, call:

```swift
.onAppear {
    let provider = LiveActiveTabTextProvider(tabManager: tabManager)
    self.claudePageProvider = provider
    FrontmostTabRegistry.shared.setFrontmost(provider)
}
```

Store `@State private var claudePageProvider: LiveActiveTabTextProvider?` on `EvoRoot` so the provider isn't deallocated (the registry holds it `weak`). Update `setFrontmost` on the existing per-window focus notification if one is wired; otherwise `.onAppear` is sufficient for the single-window walking skeleton.

- [ ] **Step 3: Build to verify it compiles**

Run: `./scripts/xcbuild-debug.sh`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
swiftformat . && swiftlint lint --fix --use-alternative-excluding
git add evo/Core/Claude/MCP/ActiveTabTextProvider.swift evo/App/EvoRoot.swift
git commit -m "feat(claude): frontmost-tab text provider registry"
```

---

## Task 6: `read_current_page` tool + engine MCP wiring

**Files:**
- Modify: `evo/Core/Claude/MCP/EvoToolServer.swift` (replace `ping` with `read_current_page`)
- Modify: `evo/Core/Claude/ClaudeEngine.swift` (write mcp-config, complete `makeSession`)
- Create: `evoTests/Claude/ReadCurrentPageToolTests.swift`

**Interfaces:**
- Consumes: `FrontmostTabRegistry` / `ActiveTabTextProvider` (Task 5), `EvoToolServer.start()` (Task 1), `ClaudeSession` (Task 3), `ClaudeBinaryLocator` (Task 4).
- Produces: `enum ReadCurrentPageTool { static func run(provider: ActiveTabTextProvider?) async -> (text: String, isError: Bool) }` (pure, testable).
- Produces: `ClaudeEngine.makeSession(workingDirectory: URL) async throws -> ClaudeSession` — resolves binary, starts `EvoToolServer`, writes an mcp-config temp file pointing at its endpoint, constructs the session.

- [ ] **Step 1: Write the failing tests for the tool handler**

```swift
import Testing
@testable import Evo

private final class StubProvider: ActiveTabTextProvider {
    let result: Result<String, PageReadError>
    init(_ r: Result<String, PageReadError>) { result = r }
    func currentPageText() async -> Result<String, PageReadError> { result }
}

struct ReadCurrentPageToolTests {
    @Test func returnsPageText() async {
        let out = await ReadCurrentPageTool.run(provider: StubProvider(.success("Hello page")))
        #expect(out.text == "Hello page")
        #expect(out.isError == false)
    }
    @Test func reportsNoActiveTab() async {
        let out = await ReadCurrentPageTool.run(provider: StubProvider(.failure(.noActiveTab)))
        #expect(out.isError == true)
        #expect(out.text.contains("no active tab"))
    }
    @Test func reportsNilProvider() async {
        let out = await ReadCurrentPageTool.run(provider: nil)
        #expect(out.isError == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -only-testing:evoTests/ReadCurrentPageToolTests
```
Expected: FAIL — `ReadCurrentPageTool` undefined.

- [ ] **Step 3: Implement the tool handler and wire it into the server**

```swift
enum ReadCurrentPageTool {
    static func run(provider: ActiveTabTextProvider?) async -> (text: String, isError: Bool) {
        guard let provider else { return ("no active tab available", true) }
        switch await provider.currentPageText() {
        case .success(let text): return (text, false)
        case .failure(.noActiveTab): return ("no active tab available", true)
        case .failure(.evalFailed(let m)): return ("failed to read page: \(m)", true)
        }
    }
}
```

In `EvoToolServer`, replace the `ping` tool: `ListTools` returns a `read_current_page` tool (empty object input schema); `CallTool` for `read_current_page` calls `await ReadCurrentPageTool.run(provider: FrontmostTabRegistry.shared.provider)` (hop to `@MainActor` to read the registry) and maps the tuple to the SDK's `CallTool.Result(content: [.text(out.text)], isError: out.isError)`.

- [ ] **Step 4: Complete `ClaudeEngine.makeSession`**

```swift
func makeSession(workingDirectory: URL) async throws -> ClaudeSession {
    let binary: String
    switch ClaudeBinaryLocator.resolve() {
    case .success(let p): binary = p
    case .failure: throw NSError(domain: "Evo.Claude", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "claude binary not found — set the path in Settings › Claude"])
    }
    let endpoint = try await EvoToolServer.shared.start()
    let config: [String: Any] = ["mcpServers": ["evo": ["type": "http", "url": endpoint.absoluteString]]]
    let data = try JSONSerialization.data(withJSONObject: config)
    let path = NSTemporaryDirectory() + "evo-mcp-\(UUID().uuidString).json"
    try data.write(to: URL(fileURLWithPath: path))
    return ClaudeSession(binaryPath: binary, workingDirectory: workingDirectory, mcpConfigPath: path)
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run the `-only-testing:evoTests/ReadCurrentPageToolTests` command.
Expected: PASS (all 3).

- [ ] **Step 6: Commit**

```bash
swiftformat . && swiftlint lint --fix --use-alternative-excluding
git add evo/Core/Claude/ evoTests/Claude/ReadCurrentPageToolTests.swift
git commit -m "feat(claude): read_current_page tool + engine mcp-config wiring"
```

---

## Task 7: `ClaudeChatManager` — bridge engine events to UI state

**Files:**
- Create: `evo/Features/Claude/State/ClaudeChatManager.swift`
- Create: `evoTests/Claude/ClaudeChatManagerTests.swift`

**Interfaces:**
- Consumes: `ClaudeEngine.shared.makeSession` (Task 6), `ClaudeEvent` (Task 2).
- Produces: `@MainActor final class ClaudeChatManager: ObservableObject` with `@Published private(set) var messages: [ChatMessage]`, `@Published private(set) var isRunning: Bool`, `func send(_ text: String)`, `func stop()`, and a testable reducer `func apply(_ event: ClaudeEvent)`.
- Produces: `struct ChatMessage: Identifiable, Equatable { let id: UUID; enum Role { case user, assistant, tool }; var role: Role; var text: String }`

- [ ] **Step 1: Write the failing tests for the reducer**

```swift
import Testing
@testable import Evo

@MainActor struct ClaudeChatManagerTests {
    @Test func appendsAssistantText() {
        let m = ClaudeChatManager(workingDirectory: URL(fileURLWithPath: NSHomeDirectory()))
        m.apply(.assistantText("Hi"))
        #expect(m.messages.last?.role == .assistant)
        #expect(m.messages.last?.text == "Hi")
    }
    @Test func toolUseAppearsAsToolRow() {
        let m = ClaudeChatManager(workingDirectory: URL(fileURLWithPath: NSHomeDirectory()))
        m.apply(.toolUse(name: "mcp__evo__read_current_page", id: "t1"))
        #expect(m.messages.last?.role == .tool)
        #expect(m.messages.last?.text.contains("read_current_page") == true)
    }
    @Test func resultClearsRunning() {
        let m = ClaudeChatManager(workingDirectory: URL(fileURLWithPath: NSHomeDirectory()))
        m.setRunningForTesting(true)
        m.apply(.result(usageUSD: 0.01))
        #expect(m.isRunning == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -only-testing:evoTests/ClaudeChatManagerTests
```
Expected: FAIL — `ClaudeChatManager` undefined.

- [ ] **Step 3: Implement the manager**

```swift
import Foundation

@MainActor final class ClaudeChatManager: ObservableObject {
    struct ChatMessage: Identifiable, Equatable {
        enum Role { case user, assistant, tool }
        let id = UUID()
        var role: Role
        var text: String
    }

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isRunning = false

    private let workingDirectory: URL
    private var session: ClaudeSession?
    private var pump: Task<Void, Never>?

    init(workingDirectory: URL) { self.workingDirectory = workingDirectory }

    func send(_ text: String) {
        messages.append(.init(role: .user, text: text))
        isRunning = true
        Task {
            do {
                if session == nil {
                    let s = try await ClaudeEngine.shared.makeSession(workingDirectory: workingDirectory)
                    session = s
                    pump = Task { for await event in s.events { self.apply(event) } }
                }
                session?.send(text)
            } catch {
                apply(.failed(error.localizedDescription))
            }
        }
    }

    func stop() { session?.interrupt(); isRunning = false }

    func apply(_ event: ClaudeEvent) {
        switch event {
        case .sessionStarted: break
        case .assistantText(let t): messages.append(.init(role: .assistant, text: t))
        case .toolUse(let name, _):
            messages.append(.init(role: .tool, text: name.replacingOccurrences(of: "mcp__evo__", with: "")))
        case .toolResult: break
        case .result: isRunning = false
        case .failed(let m): messages.append(.init(role: .assistant, text: "⚠️ \(m)")); isRunning = false
        }
    }

    func setRunningForTesting(_ v: Bool) { isRunning = v }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the `-only-testing:evoTests/ClaudeChatManagerTests` command.
Expected: PASS (all 3).

- [ ] **Step 5: Commit**

```bash
swiftformat . && swiftlint lint --fix --use-alternative-excluding
git add evo/Features/Claude/State/ClaudeChatManager.swift evoTests/Claude/ClaudeChatManagerTests.swift
git commit -m "feat(claude): ClaudeChatManager event reducer + session lifecycle"
```

---

## Task 8: Side panel UI + nested `HSplit` docking

**Files:**
- Create: `evo/Features/Claude/State/ClaudePanelManager.swift`
- Create: `evo/Features/Claude/Views/ClaudeSidePanelView.swift`
- Create: `evo/Features/Claude/Views/ClaudeMessageRow.swift`
- Modify: `evo/App/EvoRoot.swift:35-103` (construct + inject managers)
- Modify: `evo/Features/Browser/Views/BrowserSplitView.swift:78-91` (nest the panel `HSplit`)

**Interfaces:**
- Consumes: `ClaudeChatManager` (Task 7), the vendored `HSplit` (`evo/Shared/Layout/SplitView/HSplit.swift:10`).
- Produces: `@MainActor final class ClaudePanelManager: ObservableObject { @Published var isVisible: Bool; let fraction: FractionHolder }` (mirror `SidebarManager`'s holder usage).

- [ ] **Step 1: Implement `ClaudePanelManager`**

```swift
import SwiftUI

@MainActor final class ClaudePanelManager: ObservableObject {
    @Published var isVisible = false
    let fraction = FractionHolder.usingUserDefaults(0.7, key: "claude.panel.fraction")
    func toggle() { isVisible.toggle() }
}
```

(`FractionHolder` is the vendored SplitView type already used by the sidebar — confirm the exact factory name in `evo/Shared/Layout/SplitView/` and match it.)

- [ ] **Step 2: Implement `ClaudeMessageRow` and `ClaudeSidePanelView`**

```swift
import SwiftUI

struct ClaudeMessageRow: View {
    let message: ClaudeChatManager.ChatMessage
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            switch message.role {
            case .user: Image(systemName: "person.crop.circle")
            case .assistant: Image(systemName: "sparkles")
            case .tool: Image(systemName: "wrench.and.screwdriver")
            }
            Text(message.role == .tool ? "▸ \(message.text)" : message.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(message.role == .tool ? .caption.monospaced() : .body)
        .padding(.vertical, 2)
    }
}

struct ClaudeSidePanelView: View {
    @ObservedObject var chat: ClaudeChatManager
    @State private var draft = ""
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(chat.messages) { ClaudeMessageRow(message: $0).id($0.id) }
                    }.padding(12)
                }
                .onChange(of: chat.messages.count) { _, _ in
                    if let last = chat.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("Ask Claude about this page…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain).onSubmit(submit)
                Button(action: chat.isRunning ? chat.stop : submit) {
                    Image(systemName: chat.isRunning ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                }.buttonStyle(.plain).disabled(draft.isEmpty && !chat.isRunning)
            }.padding(12)
        }
        .frame(minWidth: 280)
        .background(.regularMaterial)
    }
    private func submit() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        chat.send(t); draft = ""
    }
}
```

- [ ] **Step 3: Construct + inject managers in `EvoRoot`**

In `EvoRoot.init` (`EvoRoot.swift:35`), add `@StateObject` managers mirroring the existing ones:

```swift
@StateObject private var claudeChat: ClaudeChatManager
@StateObject private var claudePanel = ClaudePanelManager()
```

Initialize `claudeChat` in `init` with `_claudeChat = StateObject(wrappedValue: ClaudeChatManager(workingDirectory: URL(fileURLWithPath: NSHomeDirectory())))`. Inject both via `.environmentObject(claudeChat)` / `.environmentObject(claudePanel)` alongside the existing `.environmentObject` calls (`EvoRoot.swift:90-103`).

- [ ] **Step 4: Nest the panel `HSplit` in `BrowserSplitView.contentView()`**

In `BrowserSplitView.swift:78-91`, read the two managers from the environment and, when `claudePanel.isVisible`, wrap the existing content in a nested `HSplit` with the web content left and `ClaudeSidePanelView(chat: claudeChat)` right, bound to `claudePanel.fraction`:

```swift
@EnvironmentObject private var claudePanel: ClaudePanelManager
@EnvironmentObject private var claudeChat: ClaudeChatManager

private func contentView() -> some View {
    Group {
        if claudePanel.isVisible {
            HSplit(left: { webContent() }, right: { ClaudeSidePanelView(chat: claudeChat) })
                .fraction(claudePanel.fraction)
                .constraints(minPFraction: 0.4, minSFraction: 0.2)
        } else {
            webContent()
        }
    }
}
```

Extract the current body of `contentView()` (the `BrowserContentContainer { … }` block) into a `webContent()` helper so both branches reuse it.

- [ ] **Step 5: Add a toggle command**

Add a keyboard toggle. In `EvoCommands` (menu) or the existing hotkey path, post/flip `claudePanel.toggle()` bound to `⌘�..` (choose a free shortcut; confirm against `CustomKeyboardShortcutManager`). Minimal acceptable version: a toolbar/sidebar button that calls `claudePanel.toggle()`.

- [ ] **Step 6: Build and verify it compiles + launches**

Run:
```bash
xcodegen && ./scripts/xcbuild-debug.sh && open ~/Library/Developer/Xcode/DerivedData/Evo-*/Build/Products/Debug/Evo.app
```
Expected: app launches; toggling shows the panel docked right of the page with a draggable divider.

- [ ] **Step 7: Commit**

```bash
swiftformat . && swiftlint lint --fix --use-alternative-excluding
git add evo/Features/Claude/ evo/App/EvoRoot.swift evo/Features/Browser/Views/BrowserSplitView.swift
git commit -m "feat(claude): side panel UI docked via nested HSplit"
```

---

## Task 9: Settings — `claude` binary path override

**Files:**
- Modify: `evo/Features/Settings/SettingsContentView.swift:4-103` (add `claude` case)
- Create: `evo/Features/Settings/Sections/ClaudeSettingsView.swift`

**Interfaces:**
- Consumes: the `UserDefaults` key `claude.binaryPath` read by `ClaudeBinaryLocator.resolve()` (Task 4).

- [ ] **Step 1: Add the settings section enum case**

In `SettingsContentView.swift`, add `case claude` to `SettingsTab` (`:4-45`) with `title = "Claude"`, `symbol = "sparkles"`, `subtitle = "AI assistant & CLI path"`. Add `case .claude: ClaudeSettingsView()` to `detailView` (`:89-103`).

- [ ] **Step 2: Implement `ClaudeSettingsView`**

```swift
import SwiftUI

struct ClaudeSettingsView: View {
    @AppStorage("claude.binaryPath") private var binaryPath = ""
    @State private var resolved = ""
    var body: some View {
        Form {
            Section("claude CLI") {
                TextField("Binary path (leave blank to auto-detect)", text: $binaryPath)
                Button("Detect") {
                    if case .success(let p) = ClaudeBinaryLocator.resolve() { resolved = p }
                }
                if !resolved.isEmpty { Text("Resolved: \(resolved)").font(.caption).foregroundStyle(.secondary) }
            }
        }.formStyle(.grouped).padding()
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodegen && ./scripts/xcbuild-debug.sh`
Expected: build succeeds; Settings shows a "Claude" section with a path field + Detect button.

- [ ] **Step 4: Commit**

```bash
swiftformat . && swiftlint lint --fix --use-alternative-excluding
git add evo/Features/Settings/
git commit -m "feat(claude): settings section for claude binary path"
```

---

## Task 10: End-to-end manual verification

**Files:** none (verification only).

- [ ] **Step 1: Run the full test suite**

Run:
```bash
xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```
Expected: all `evoTests` pass.

- [ ] **Step 2: Manual walking-skeleton check**

1. Launch the debug app.
2. Open a content-rich page (e.g. a news article).
3. Toggle the Claude panel.
4. Type: "Summarize the page I'm looking at in one sentence."
5. Confirm: a `▸ read_current_page` tool row appears, then an assistant summary that clearly reflects *that page's* content (proving the tool read the real, authenticated tab).
6. Press Stop mid-run on a longer prompt; confirm the run halts.

- [ ] **Step 3: Confirm auth reuse**

Open a page behind your existing login (a site you're already signed into), ask Claude to read it, and confirm it sees logged-in content — proving the tool inherits the WebView's cookies.

- [ ] **Step 4: Final commit (docs)**

Update `FORK_PATCHES.md` / `CLAUDE.md` only if new cross-cutting facts emerged (e.g. the confirmed MCP transport path). Commit if changed:

```bash
git add -A && git commit -m "docs(claude): record walking-skeleton verification + MCP transport decision"
```

---

## Self-Review

**Spec coverage:**
- Engine host (spawn CLI, stream-json, lifecycle) → Tasks 3, 4, 6. ✅
- Side panel surface → Task 8. ✅
- `read_current_page` over own WebView → Tasks 1, 5, 6. ✅
- MCP-HTTP-server spike as step 1 → Task 1. ✅
- Error handling (binary missing, crash, tool error, malformed line, port) → Tasks 3 (crash/malformed/launch), 4 (missing), 6 (tool error), 1 (port). ✅
- Testing (parser fixtures, tool handler, gated integration) → Tasks 2, 6, 10. ✅
- Open decisions (working dir default `~`, binary resolution, frontmost window) → Tasks 8 (workdir `NSHomeDirectory()`), 4 & 9 (binary), 5 (frontmost). ✅
- Out-of-scope items (control tools, other surfaces, 1Password, repos, remote, sandbox) → none introduced. ✅

**Placeholder scan:** The only intentionally-open element is the MCP server transport internals in Task 1 — correct, because that task *is* the spike whose job is to resolve it; both branches (SDK transport / `Network.framework`) are named with concrete next steps. No "TODO/handle edge cases" placeholders elsewhere.

**Type consistency:** `ClaudeEvent` cases, `ChatMessage`/`Role`, `ActiveTabTextProvider.currentPageText`, `PageReadError`, `EvoToolServer.start() -> URL`, `ClaudeEngine.makeSession(workingDirectory:)`, `ClaudeBinaryLocator.resolve` signatures are used consistently across Tasks 2–9. ✅
