# Evo Debug Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Debug-only localhost HTTP control server inside Evo so Claude can drive and observe the browser (navigate, eval JS, read the native autofill overlay, send key commands, screenshot) against deterministic fixtures with a mock password provider.

**Architecture:** Four units: `MockPasswordProvider` behind the existing `PasswordProvider` seam; `DebugHarnessRegistry` (weak per-window `TabManager`/`HistoryManager` handles registered by `EvoRoot`); `DebugHarnessHTTP` (pure HTTP/1.1 parse/serialize); `DebugHarnessServer` + `DebugHarnessRouter` (NWListener glue + route handlers hopping to `@MainActor`). Everything is wrapped in `#if DEBUG` and compiles to nothing in Release.

**Tech Stack:** Swift 5 / SwiftUI host app, Network.framework (`NWListener`, no new dependencies), Swift Testing (`import Testing`, `@testable import Evo`), Python 3 stdlib for the fixture server.

**Spec:** `docs/superpowers/specs/2026-07-16-debug-harness-design.md`

## Global Constraints

- Every new Swift file in this plan is wrapped **entirely** in `#if DEBUG` / `#endif` (first and last lines) unless a task says otherwise.
- Server binds `127.0.0.1` only. Port: `EVO_HARNESS_PORT` env var, default `4590`. Fixture server port: `4599`.
- Auth token: random per launch, written to `~/Library/Application Support/Evo/harness-token` (0600), required in `X-Evo-Harness-Token` header on every request except none (all routes require it); mismatch → 401.
- No route ever returns a secret unless the active provider is `mock`. (v1 exposes no reveal route at all — do not add one.)
- SwiftLint: no force unwrapping, no implicitly unwrapped optionals in new code. SwiftFormat: 4-space indent, 120 col.
- After creating new Swift files, run `xcodegen` before building (the project is generated).
- Build: `./scripts/xcbuild-debug.sh`. Tests: `xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -only-testing:<filter>`.
- Test framework is Swift Testing (`import Testing`, `#expect`, plain `struct` suites) — NOT XCTest.
- Commit after every task. Markdown files: no hard-wrapping; one paragraph per line.

---

### Task 1: MockPasswordProvider

**Files:**
- Modify: `evo/Features/Passwords/Providers/PasswordProviderTypes.swift` (add `mock` case to `ProviderItemRef`)
- Modify: `evo/Features/Passwords/Services/PasswordManagerProviderRegistry.swift` (add `mock` kind, descriptor, provider wiring)
- Create: `evo/Features/Passwords/Providers/MockPasswordProvider.swift`
- Test: `evoTests/Passwords/MockPasswordProviderTests.swift`

**Interfaces:**
- Consumes: `PasswordProvider` protocol (`evo/Features/Passwords/Providers/PasswordProvider.swift`), `ProviderCredential`, `ProviderItemRef`, `RevealedCredential`, `SaveTarget`, `ProviderState`, `FieldPurpose`, `StructuredCategory`, `ProviderStructuredItem` (all in `PasswordProviderTypes.swift`).
- Produces: `MockPasswordProvider` (class, `PasswordProvider` conformance), `PasswordManagerProviderKind.mock`, `ProviderItemRef.mock(itemID: String)`. Registry returns the mock from `activeProvider(for: .mock)` in Debug. Task 7's `/provider` route relies on `PasswordManagerProviderKind(rawValue: "mock")` resolving in Debug builds.

- [ ] **Step 1: Write the failing test**

Create `evoTests/Passwords/MockPasswordProviderTests.swift`:

```swift
import Foundation
import Testing
@testable import Evo

struct MockPasswordProviderTests {
    @Test func credentialsMatchHost() async {
        let provider = MockPasswordProvider()
        let url = URL(string: "http://127.0.0.1:4599/login-basic.html")
        #expect(url != nil)
        guard let url else { return }
        let creds = await provider.credentials(for: url, containerID: nil)
        #expect(creds.count == 2)
        #expect(creds.allSatisfy { $0.host == "127.0.0.1" })
    }

    @Test func credentialsForUnknownHostAreEmpty() async {
        let provider = MockPasswordProvider()
        guard let url = URL(string: "https://example.org/") else { return }
        let creds = await provider.credentials(for: url, containerID: nil)
        #expect(creds.isEmpty)
    }

    @Test func revealReturnsDeterministicSecret() async throws {
        let provider = MockPasswordProvider()
        guard let url = URL(string: "http://127.0.0.1:4599/") else { return }
        let creds = await provider.credentials(for: url, containerID: nil)
        let alice = creds.first { $0.username == "alice@example.com" }
        #expect(alice != nil)
        guard let alice else { return }
        let revealed = try await provider.reveal(alice)
        #expect(revealed.password == "correct-horse-battery-staple")
    }

    @Test func totpOnlyForTotpCredential() async throws {
        let provider = MockPasswordProvider()
        guard let url = URL(string: "http://localhost:4599/") else { return }
        let creds = await provider.credentials(for: url, containerID: nil)
        #expect(creds.count == 1)
        guard let carol = creds.first else { return }
        #expect(carol.hasTotp)
        let code = try await provider.totp(for: carol)
        #expect(code == "123456")
    }

    @Test func saveIsRecorded() async throws {
        let provider = MockPasswordProvider()
        guard let url = URL(string: "http://127.0.0.1:4599/signup.html") else { return }
        try await provider.save(url: url, username: "new@example.com", password: "pw-1", target: .evoContainer(nil))
        #expect(provider.savedItems.count == 1)
        #expect(provider.savedItems.first?.username == "new@example.com")
    }

    @Test func structuredItemsAndFillValues() async throws {
        let provider = MockPasswordProvider()
        let cards = await provider.structuredItems(.creditCard)
        #expect(cards.count == 1)
        guard let card = cards.first else { return }
        let values = try await provider.fillValues(for: card.ref)
        #expect(values[.cardNumber] == "4111111111111111")
        #expect(values[.cvv] == "123")
        let identities = await provider.structuredItems(.identity)
        #expect(identities.count == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -only-testing:evoTests/MockPasswordProviderTests 2>&1 | tail -20`
Expected: BUILD FAILURE — `cannot find 'MockPasswordProvider' in scope`.

- [ ] **Step 3: Add the `mock` ref case**

In `evo/Features/Passwords/Providers/PasswordProviderTypes.swift`, extend `ProviderItemRef`:

```swift
/// How to fetch a credential back from its owning provider.
enum ProviderItemRef: Hashable, Sendable {
    case evo(persistentReference: Data)
    case onePassword(accountName: String, vaultID: String, itemID: String)
    case mock(itemID: String)
}
```

- [ ] **Step 4: Write MockPasswordProvider**

Create `evo/Features/Passwords/Providers/MockPasswordProvider.swift`:

```swift
#if DEBUG
    import Foundation

    /// Deterministic in-memory provider for the debug harness. Never touches Keychain or 1Password.
    /// Vault contents are fixed constants so harness assertions are stable across runs.
    final class MockPasswordProvider: PasswordProvider {
        struct SavedItem: Equatable {
            let url: URL
            let username: String
            let password: String
        }

        private struct MockLogin {
            let id: String
            let title: String
            let username: String
            let password: String
            let host: String
            let totp: String?
        }

        private let logins: [MockLogin] = [
            MockLogin(
                id: "mock-login-alice",
                title: "Fixture Site A",
                username: "alice@example.com",
                password: "correct-horse-battery-staple",
                host: "127.0.0.1",
                totp: nil
            ),
            MockLogin(
                id: "mock-login-bob",
                title: "Fixture Site A (alt)",
                username: "bob@example.com",
                password: "hunter2-bob",
                host: "127.0.0.1",
                totp: nil
            ),
            MockLogin(
                id: "mock-login-carol",
                title: "Fixture Site B",
                username: "carol@example.com",
                password: "carol-pass-3",
                host: "localhost",
                totp: "123456"
            ),
        ]

        private(set) var savedItems: [SavedItem] = []

        var usesBuiltInOverlay: Bool { true }
        var state: ProviderState { .ready }

        func credentials(for url: URL, containerID _: UUID?) async -> [ProviderCredential] {
            guard let host = url.host else { return [] }
            return logins.filter { $0.host == host }.map { login in
                ProviderCredential(
                    id: login.id,
                    ref: .mock(itemID: login.id),
                    title: login.title,
                    username: login.username,
                    host: login.host,
                    accountLabel: "Mock Vault",
                    hasTotp: login.totp != nil
                )
            }
        }

        func reveal(_ credential: ProviderCredential) async throws -> RevealedCredential {
            guard case let .mock(itemID) = credential.ref,
                  let login = logins.first(where: { $0.id == itemID })
            else {
                throw MockProviderError.itemNotFound
            }
            return RevealedCredential(username: login.username, password: login.password)
        }

        func save(url: URL, username: String, password: String, target _: SaveTarget) async throws {
            savedItems.append(SavedItem(url: url, username: username, password: password))
        }

        func totp(for credential: ProviderCredential) async throws -> String? {
            guard case let .mock(itemID) = credential.ref else { return nil }
            return logins.first(where: { $0.id == itemID })?.totp
        }

        func structuredItems(_ category: StructuredCategory) async -> [ProviderStructuredItem] {
            switch category {
            case .creditCard:
                return [ProviderStructuredItem(
                    id: "mock-card-visa",
                    ref: .mock(itemID: "mock-card-visa"),
                    category: .creditCard,
                    title: "Mock Visa",
                    subtitle: "•••• 1111"
                )]
            case .identity:
                return [ProviderStructuredItem(
                    id: "mock-identity-alice",
                    ref: .mock(itemID: "mock-identity-alice"),
                    category: .identity,
                    title: "Alice Mock",
                    subtitle: "1 Fixture Way"
                )]
            }
        }

        func fillValues(for ref: ProviderItemRef) async throws -> [FieldPurpose: String] {
            guard case let .mock(itemID) = ref else { throw MockProviderError.itemNotFound }
            switch itemID {
            case "mock-card-visa":
                return [
                    .cardholderName: "Alice Mock",
                    .cardNumber: "4111111111111111",
                    .expMonth: "12",
                    .expYear: "2030",
                    .expDate: "12/2030",
                    .cvv: "123",
                ]
            case "mock-identity-alice":
                return [
                    .givenName: "Alice",
                    .familyName: "Mock",
                    .fullName: "Alice Mock",
                    .addressLine1: "1 Fixture Way",
                    .city: "Testville",
                    .state: "CA",
                    .postalCode: "94100",
                    .country: "US",
                    .phone: "+1 555 010 0001",
                    .email: "alice@example.com",
                    .organization: "SK Productions",
                ]
            default:
                throw MockProviderError.itemNotFound
            }
        }
    }

    enum MockProviderError: Error {
        case itemNotFound
    }
#endif
```

- [ ] **Step 5: Wire the registry**

In `evo/Features/Passwords/Services/PasswordManagerProviderRegistry.swift`:

Add the kind case:

```swift
enum PasswordManagerProviderKind: String, CaseIterable, Codable, Identifiable {
    case evo
    case onePassword
    case bitwarden
    case mock

    var id: String {
        rawValue
    }
}
```

Replace the `providers` literal with a Debug-conditional builder (keep the existing evo and onePassword descriptors verbatim, and keep the commented-out bitwarden block where it is):

```swift
    let providers: [PasswordManagerProviderDescriptor] = {
        var list: [PasswordManagerProviderDescriptor] = [
            PasswordManagerProviderDescriptor(
                kind: .evo,
                title: "Evo Passwords",
                summary: "Store encrypted credentials in Evo and show Evo's autofill overlay.",
                vaultStoredInEvo: true,
                autofillMode: .builtInOverlay,
                isAvailable: true
            ),
            PasswordManagerProviderDescriptor(
                kind: .onePassword,
                title: "1Password",
                summary: "Autofill from your 1Password vaults using the 1Password desktop app.",
                vaultStoredInEvo: false,
                autofillMode: .builtInOverlay,
                isAvailable: true
            ),
        ]
        #if DEBUG
            list.append(PasswordManagerProviderDescriptor(
                kind: .mock,
                title: "Mock (Debug)",
                summary: "Deterministic fake vault for the debug harness. Debug builds only.",
                vaultStoredInEvo: false,
                autofillMode: .builtInOverlay,
                isAvailable: true
            ))
        #endif
        return list
    }()
```

Add the provider instance and the `activeProvider` arm:

```swift
    #if DEBUG
        @MainActor private lazy var mockProvider = MockPasswordProvider()
    #endif

    @MainActor
    func activeProvider(for kind: PasswordManagerProviderKind) -> PasswordProvider {
        switch kind {
        #if DEBUG
            case .mock: return mockProvider
        #endif
        case .onePassword: return onePasswordProvider
        default: return evoProvider
        }
    }
```

Note: in Release, `.mock` falls through to `default` → `evoProvider`, so a leftover `settings.passwords.provider = "mock"` default degrades safely.

- [ ] **Step 6: Regenerate project and run tests**

Run: `xcodegen && xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -only-testing:evoTests/MockPasswordProviderTests 2>&1 | tail -10`
Expected: `** TEST SUCCEEDED **`, 6 tests pass.

- [ ] **Step 7: Check for exhaustive-switch fallout**

Run: `./scripts/xcbuild-debug.sh 2>&1 | grep -E "error|warning: switch" | head -20`
`ProviderItemRef` gained a case; any exhaustive `switch` over it elsewhere (e.g. in `PasswordAutofillCoordinator` or `OnePasswordProvider`) now fails to compile. For each error, add a safe arm, e.g. `case .mock: return` (or `break` / empty array — match the function's neutral value). Expected after fixes: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add -A evo evoTests
git commit -m "feat(debug-harness): MockPasswordProvider behind the PasswordProvider seam"
```

---

### Task 2: HTTP request parsing and response serialization (pure)

**Files:**
- Create: `evo/Core/Services/Debug/DebugHarnessHTTP.swift`
- Test: `evoTests/DebugHarness/DebugHarnessHTTPTests.swift`

**Interfaces:**
- Consumes: nothing app-specific (Foundation only).
- Produces, all inside `#if DEBUG`:
  - `struct HarnessHTTPRequest { let method: String; let path: String; let query: [String: String]; let headers: [String: String]; let body: Data }` — header keys lowercased.
  - `enum HarnessHTTPParser { static func parse(_ data: Data) -> HarnessParseResult }` with `enum HarnessParseResult { case incomplete; case invalid; case request(HarnessHTTPRequest) }` — `incomplete` means "keep reading from the socket".
  - `struct HarnessHTTPResponse { let status: Int; let body: Data; func serialized() -> Data; static func json(_ object: Any, status: Int) -> HarnessHTTPResponse; static func error(_ message: String, status: Int) -> HarnessHTTPResponse }`.

- [ ] **Step 1: Write the failing tests**

Create `evoTests/DebugHarness/DebugHarnessHTTPTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -only-testing:evoTests/DebugHarnessHTTPTests 2>&1 | tail -10`
Expected: BUILD FAILURE — `cannot find 'HarnessHTTPParser' in scope`.

- [ ] **Step 3: Implement**

Create `evo/Core/Services/Debug/DebugHarnessHTTP.swift`:

```swift
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
```

- [ ] **Step 4: Regenerate, run tests**

Run: `xcodegen && xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -only-testing:evoTests/DebugHarnessHTTPTests 2>&1 | tail -10`
Expected: `** TEST SUCCEEDED **`, 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add evo/Core/Services/Debug evoTests/DebugHarness
git commit -m "feat(debug-harness): pure HTTP/1.1 parser and JSON response serializer"
```

---

### Task 3: DebugHarnessRegistry + EvoRoot registration

**Files:**
- Create: `evo/Core/Services/Debug/DebugHarnessRegistry.swift`
- Modify: `evo/App/EvoRoot.swift` (register in `.onAppear` around line 123, unregister in `.onDisappear` around line 120)
- Test: `evoTests/DebugHarness/DebugHarnessRegistryTests.swift`

**Interfaces:**
- Consumes: `TabManager` (`@MainActor ObservableObject`, `evo/Features/Tabs/State/TabManager.swift`), `HistoryManager`, `Tab` (`id: UUID`, `url: URL`, `title: String`, `browserPage: BrowserPage?`).
- Produces, inside `#if DEBUG`:
  - `@MainActor final class DebugHarnessRegistry` with `static let shared`, plus `init()` left internal so tests can build isolated instances.
  - `func register(tabManager: TabManager, historyManager: HistoryManager, isPrivate: Bool) -> UUID`
  - `func unregister(_ id: UUID)`
  - `struct WindowSnapshot { let id: UUID; let isPrivate: Bool; let tabManager: TabManager; let historyManager: HistoryManager }`
  - `func snapshots() -> [WindowSnapshot]` — prunes dead weak refs.
  - `func findTab(_ tabID: UUID) -> (tab: Tab, manager: TabManager)?` — searches every registered window's `tabManager.activeContainer`-independent full tab list via `manager.allTabs()` if such API exists; otherwise iterate `container.tabs` across `manager` containers. **Implementer: check `TabManager` for the canonical "all tabs" accessor before writing this; `openTab` at `TabManager.swift:294` shows tabs live on `container.tabs`.**

- [ ] **Step 1: Write the failing tests**

Create `evoTests/DebugHarness/DebugHarnessRegistryTests.swift`:

```swift
import Foundation
import Testing
@testable import Evo

@MainActor
struct DebugHarnessRegistryTests {
    @Test func registerAndSnapshot() {
        let registry = DebugHarnessRegistry()
        let tabManager = TabManager()
        let historyManager = HistoryManager()
        let id = registry.register(tabManager: tabManager, historyManager: historyManager, isPrivate: false)
        let snapshots = registry.snapshots()
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.id == id)
        #expect(snapshots.first?.isPrivate == false)
    }

    @Test func unregisterRemoves() {
        let registry = DebugHarnessRegistry()
        let tabManager = TabManager()
        let historyManager = HistoryManager()
        let id = registry.register(tabManager: tabManager, historyManager: historyManager, isPrivate: true)
        registry.unregister(id)
        #expect(registry.snapshots().isEmpty)
    }

    @Test func deadReferencesArePruned() {
        let registry = DebugHarnessRegistry()
        var tabManager: TabManager? = TabManager()
        let historyManager = HistoryManager()
        if let manager = tabManager {
            _ = registry.register(tabManager: manager, historyManager: historyManager, isPrivate: false)
        }
        tabManager = nil
        #expect(registry.snapshots().isEmpty)
    }
}
```

**Implementer note:** if `TabManager()` / `HistoryManager()` need constructor arguments (e.g. a `ModelContext`), build them the way existing tests in `evoTests/` do — check `evoTests/` for prior art and adapt the three tests' construction lines only; the assertions stand.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -only-testing:evoTests/DebugHarnessRegistryTests 2>&1 | tail -10`
Expected: BUILD FAILURE — `cannot find 'DebugHarnessRegistry' in scope`.

- [ ] **Step 3: Implement the registry**

Create `evo/Core/Services/Debug/DebugHarnessRegistry.swift`:

```swift
#if DEBUG
    import Foundation

    /// Debug-only bridge from the singleton harness server to per-window state.
    /// EvoRoot registers its managers on appear; references are weak so a closed
    /// window never keeps its managers alive.
    @MainActor
    final class DebugHarnessRegistry {
        static let shared = DebugHarnessRegistry()

        struct WindowSnapshot {
            let id: UUID
            let isPrivate: Bool
            let tabManager: TabManager
            let historyManager: HistoryManager
        }

        private struct Entry {
            let id: UUID
            let isPrivate: Bool
            weak var tabManager: TabManager?
            weak var historyManager: HistoryManager?
        }

        private var entries: [Entry] = []

        func register(tabManager: TabManager, historyManager: HistoryManager, isPrivate: Bool) -> UUID {
            let id = UUID()
            entries.append(Entry(id: id, isPrivate: isPrivate, tabManager: tabManager, historyManager: historyManager))
            return id
        }

        func unregister(_ id: UUID) {
            entries.removeAll { $0.id == id }
        }

        func snapshots() -> [WindowSnapshot] {
            entries.removeAll { $0.tabManager == nil || $0.historyManager == nil }
            return entries.compactMap { entry in
                guard let tabManager = entry.tabManager, let historyManager = entry.historyManager else { return nil }
                return WindowSnapshot(
                    id: entry.id,
                    isPrivate: entry.isPrivate,
                    tabManager: tabManager,
                    historyManager: historyManager
                )
            }
        }

        func findTab(_ tabID: UUID) -> (tab: Tab, manager: TabManager)? {
            for snapshot in snapshots() {
                for container in snapshot.tabManager.containers {
                    if let tab = container.tabs.first(where: { $0.id == tabID }) {
                        return (tab, snapshot.tabManager)
                    }
                }
            }
            return nil
        }
    }
#endif
```

**Implementer note:** `findTab` assumes `TabManager` exposes `containers` with `tabs`. Verify the actual property names (`grep -n "var containers\|activeContainer" evo/Features/Tabs/State/TabManager.swift`) and adjust — the contract is "search every tab in every container of every registered window".

- [ ] **Step 4: Register from EvoRoot**

In `evo/App/EvoRoot.swift`: add a state field near the other `@State` declarations (around line 35):

```swift
    #if DEBUG
        @State private var harnessRegistrationID: UUID?
    #endif
```

Inside the existing `.onAppear` block (around line 123), add at the top:

```swift
            #if DEBUG
                harnessRegistrationID = DebugHarnessRegistry.shared.register(
                    tabManager: tabManager,
                    historyManager: historyManager,
                    isPrivate: privacyMode.isPrivate
                )
            #endif
```

Inside the existing `.onDisappear` block (around line 120), add:

```swift
            #if DEBUG
                if let harnessRegistrationID {
                    DebugHarnessRegistry.shared.unregister(harnessRegistrationID)
                }
            #endif
```

**Implementer note:** the private flag lives on `PrivacyMode` (`@StateObject private var privacyMode: PrivacyMode`, `@Published var isPrivate: Bool`). If `EvoRoot` also has a plain `isPrivate` init parameter stored differently, prefer whatever the surrounding code reads.

- [ ] **Step 5: Regenerate, test, build**

Run: `xcodegen && xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -only-testing:evoTests/DebugHarnessRegistryTests 2>&1 | tail -10 && ./scripts/xcbuild-debug.sh 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **` (3 tests), then `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add evo/Core/Services/Debug evo/App/EvoRoot.swift evoTests/DebugHarness
git commit -m "feat(debug-harness): per-window registry with weak manager handles"
```

---

### Task 4: DebugHarnessServer — listener, token auth, /health

**Files:**
- Create: `evo/Core/Services/Debug/DebugHarnessServer.swift`
- Create: `evo/Core/Services/Debug/DebugHarnessRouter.swift` (skeleton with `/health` only)
- Modify: `evo/App/EvoApp.swift:11-14` (start server inside the existing `#if DEBUG` block in `applicationDidFinishLaunching`)

**Interfaces:**
- Consumes: `HarnessHTTPParser`, `HarnessHTTPResponse`, `HarnessHTTPRequest` (Task 2).
- Produces, inside `#if DEBUG`:
  - `final class DebugHarnessServer` with `static let shared`, `func start()`, `private(set) var token: String`.
  - `enum DebugHarnessRouter { @MainActor static func route(_ request: HarnessHTTPRequest) async -> HarnessHTTPResponse }` — Tasks 5–7 add cases to this function's `switch (request.method, request.path)`.
  - Token file at `~/Library/Application Support/Evo/harness-token`, permissions 0600.

- [ ] **Step 1: Implement the router skeleton**

Create `evo/Core/Services/Debug/DebugHarnessRouter.swift`:

```swift
#if DEBUG
    import Foundation

    enum DebugHarnessRouter {
        @MainActor
        static func route(_ request: HarnessHTTPRequest) async -> HarnessHTTPResponse {
            switch (request.method, request.path) {
            case ("GET", "/health"):
                return HarnessHTTPResponse.json([
                    "ok": true,
                    "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                    "pid": Int(ProcessInfo.processInfo.processIdentifier),
                ])
            default:
                return HarnessHTTPResponse.error("no route for \(request.method) \(request.path)", status: 404)
            }
        }
    }
#endif
```

- [ ] **Step 2: Implement the server**

Create `evo/Core/Services/Debug/DebugHarnessServer.swift`:

```swift
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
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
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
```

- [ ] **Step 3: Start it at launch**

In `evo/App/EvoApp.swift`, the existing Debug block at lines 11–14 becomes:

```swift
        #if DEBUG
            Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/macOSInjection.bundle")?.load()
            Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/macOSSwiftUISupport.bundle")?.load()
            DebugHarnessServer.shared.start()
        #endif
```

- [ ] **Step 4: Build, launch, verify by hand**

```bash
xcodegen && ./scripts/xcbuild-debug.sh && open ~/Library/Developer/Xcode/DerivedData/Evo-*/Build/Products/Debug/Evo.app
sleep 3
TOKEN=$(cat ~/Library/Application\ Support/Evo/harness-token)
curl -s -H "X-Evo-Harness-Token: $TOKEN" http://127.0.0.1:4590/health
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:4590/health
```

Expected: first curl prints `{"ok":true,"pid":<n>,"version":"0.2.14"}`; second prints `401`.

- [ ] **Step 5: Verify port-in-use resilience**

```bash
python3 -c "import socket,time; s=socket.socket(); s.bind(('127.0.0.1',4591)); s.listen(); time.sleep(30)" &
pkill -f "Evo.app/Contents/MacOS/Evo"; EVO_HARNESS_PORT=4591 ~/Library/Developer/Xcode/DerivedData/Evo-*/Build/Products/Debug/Evo.app/Contents/MacOS/Evo &
```

Expected: app launches and browses normally (harness logs a failure, nothing crashes). Then `pkill -f "Evo.app"` and kill the python job.

- [ ] **Step 6: Commit**

```bash
git add evo/Core/Services/Debug evo/App/EvoApp.swift
git commit -m "feat(debug-harness): NWListener HTTP server with token auth and /health"
```

---

### Task 5: Discovery and navigation routes — /windows, /tabs, /navigate

**Files:**
- Modify: `evo/Core/Services/Debug/DebugHarnessRouter.swift`

**Interfaces:**
- Consumes: `DebugHarnessRegistry.shared.snapshots()`, `.findTab(_:)` (Task 3); `TabManager.openTab(url:historyManager:downloadManager:focusAfterOpening:isPrivate:loadSilently:)` (`TabManager.swift:294`); `Tab.id/.url/.title`; `BrowserPage.evaluateJavaScript(_:completion:)` (`BrowserPage.swift:154`).
- Produces routes:
  - `GET /windows` → `[{windowID, isPrivate, tabCount}]`
  - `GET /tabs?window=<uuid>` (window optional → all windows) → `[{tabID, windowID, url, title, isActive}]`
  - `POST /navigate` body `{"url": "...", "tabID": "<uuid optional>"}` → `{tabID}`; with `tabID` navigates the existing tab via JS `location.assign`, without it opens a new tab in the first (or matching) window.

- [ ] **Step 1: Add routes**

In `DebugHarnessRouter.swift`, add cases to the `switch` before `default`:

```swift
            case ("GET", "/windows"):
                let windows = DebugHarnessRegistry.shared.snapshots().map { snapshot -> [String: Any] in
                    let tabCount = snapshot.tabManager.containers.reduce(0) { $0 + $1.tabs.count }
                    return [
                        "windowID": snapshot.id.uuidString,
                        "isPrivate": snapshot.isPrivate,
                        "tabCount": tabCount,
                    ]
                }
                return HarnessHTTPResponse.json(windows)

            case ("GET", "/tabs"):
                var snapshots = DebugHarnessRegistry.shared.snapshots()
                if let windowRaw = request.query["window"] {
                    guard let windowID = UUID(uuidString: windowRaw) else {
                        return HarnessHTTPResponse.error("bad window id", status: 400)
                    }
                    snapshots = snapshots.filter { $0.id == windowID }
                }
                var tabs: [[String: Any]] = []
                for snapshot in snapshots {
                    for container in snapshot.tabManager.containers {
                        for tab in container.tabs {
                            tabs.append([
                                "tabID": tab.id.uuidString,
                                "windowID": snapshot.id.uuidString,
                                "url": tab.url.absoluteString,
                                "title": tab.title,
                                "isActive": tab.id == snapshot.tabManager.activeTab?.id,
                            ])
                        }
                    }
                }
                return HarnessHTTPResponse.json(tabs)

            case ("POST", "/navigate"):
                guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                      let urlString = payload["url"] as? String,
                      let url = URL(string: urlString)
                else {
                    return HarnessHTTPResponse.error("body must be {\"url\": \"...\"}", status: 400)
                }
                if let tabRaw = payload["tabID"] as? String {
                    guard let tabID = UUID(uuidString: tabRaw),
                          let found = DebugHarnessRegistry.shared.findTab(tabID)
                    else {
                        return HarnessHTTPResponse.error("unknown tab", status: 404)
                    }
                    let escaped = url.absoluteString
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "'", with: "\\'")
                    found.tab.browserPage?.evaluateJavaScript("location.assign('\(escaped)')")
                    return HarnessHTTPResponse.json(["tabID": found.tab.id.uuidString])
                }
                guard let snapshot = DebugHarnessRegistry.shared.snapshots().first else {
                    return HarnessHTTPResponse.error("no windows registered", status: 404)
                }
                let newTab = snapshot.tabManager.openTab(
                    url: url,
                    historyManager: snapshot.historyManager,
                    focusAfterOpening: true,
                    isPrivate: snapshot.isPrivate
                )
                guard let newTab else {
                    return HarnessHTTPResponse.error("openTab returned nil (no active container?)", status: 500)
                }
                return HarnessHTTPResponse.json(["tabID": newTab.id.uuidString])
```

**Implementer note:** verify `TabManager.containers` is the real accessor (see Task 3 note); if containers hang off a different property (`tabContainers`, `spaces`…), adapt all three routes consistently.

- [ ] **Step 2: Build and verify by hand**

```bash
./scripts/xcbuild-debug.sh && pkill -f "Evo.app/Contents/MacOS/Evo"; open ~/Library/Developer/Xcode/DerivedData/Evo-*/Build/Products/Debug/Evo.app
sleep 3
TOKEN=$(cat ~/Library/Application\ Support/Evo/harness-token)
H="X-Evo-Harness-Token: $TOKEN"
curl -s -H "$H" http://127.0.0.1:4590/windows
curl -s -H "$H" -X POST -d '{"url":"https://example.com"}' http://127.0.0.1:4590/navigate
curl -s -H "$H" http://127.0.0.1:4590/tabs
```

Expected: `/windows` returns one entry; `/navigate` returns a `tabID`; `/tabs` lists a tab whose url contains `example.com`. Visually: a new tab opened in the running app.

- [ ] **Step 3: Commit**

```bash
git add evo/Core/Services/Debug/DebugHarnessRouter.swift
git commit -m "feat(debug-harness): /windows, /tabs, /navigate routes"
```

---

### Task 6: Observation routes — /eval and /screenshot

**Files:**
- Modify: `evo/Core/Services/Debug/DebugHarnessRouter.swift`

**Interfaces:**
- Consumes: `BrowserPage.evaluateJavaScript(_:completion:)` and `BrowserPage.takeSnapshot(configuration:completion:)` (`BrowserPage.swift:154-168`), `BrowserSnapshotConfiguration` (same file area — check its init; it has `afterScreenUpdates` and optional `rect`).
- Produces routes:
  - `POST /eval` body `{"tabID": "...", "js": "..."}` → `{"result": <json>}`; JS exception → 200 with `{"error": ..., "jsException": true}`; 5s timeout → 504.
  - `POST /screenshot` body `{"scope": "page"|"window", "tabID": "<required for page>", "path": "/abs/out.png"}` → `{"path", "width", "height"}`.
- Helper produced for Task 7 reuse: `static func harnessTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T`.

- [ ] **Step 1: Add a timeout helper and the eval route**

In `DebugHarnessRouter.swift` add inside the enum (outside `route`):

```swift
        enum HarnessError: Error {
            case timeout
        }

        static func harnessTimeout<T: Sendable>(
            seconds: Double,
            _ operation: @escaping @Sendable () async throws -> T
        ) async throws -> T {
            try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask { try await operation() }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    throw HarnessError.timeout
                }
                guard let first = try await group.next() else { throw HarnessError.timeout }
                group.cancelAll()
                return first
            }
        }
```

Add the route case:

```swift
            case ("POST", "/eval"):
                guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                      let tabRaw = payload["tabID"] as? String,
                      let tabID = UUID(uuidString: tabRaw),
                      let js = payload["js"] as? String
                else {
                    return HarnessHTTPResponse.error("body must be {\"tabID\", \"js\"}", status: 400)
                }
                guard let found = DebugHarnessRegistry.shared.findTab(tabID),
                      let page = found.tab.browserPage
                else {
                    return HarnessHTTPResponse.error("unknown tab or no page", status: 404)
                }
                do {
                    let outcome: Result<Any?, Error> = try await Self.harnessTimeout(seconds: 5) {
                        await withCheckedContinuation { continuation in
                            Task { @MainActor in
                                page.evaluateJavaScript(js) { value, error in
                                    if let error {
                                        continuation.resume(returning: .failure(error))
                                    } else {
                                        continuation.resume(returning: .success(value))
                                    }
                                }
                            }
                        }
                    }
                    switch outcome {
                    case let .success(value):
                        return HarnessHTTPResponse.json(["result": Self.jsonSafe(value)])
                    case let .failure(error):
                        return HarnessHTTPResponse.json([
                            "error": error.localizedDescription,
                            "jsException": true,
                        ])
                    }
                } catch {
                    return HarnessHTTPResponse.error("eval timed out", status: 504)
                }
```

Add the JSON-safety helper inside the enum:

```swift
        /// WebKit hands back NSString/NSNumber/NSArray/NSDictionary/NSNull. Anything else is stringified.
        static func jsonSafe(_ value: Any?) -> Any {
            guard let value else { return NSNull() }
            if JSONSerialization.isValidJSONObject(["v": value]) { return value }
            return String(describing: value)
        }
```

- [ ] **Step 2: Add the screenshot route**

```swift
            case ("POST", "/screenshot"):
                guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                      let scope = payload["scope"] as? String,
                      let path = payload["path"] as? String,
                      path.hasPrefix("/")
                else {
                    return HarnessHTTPResponse.error("body must be {\"scope\": \"page\"|\"window\", \"path\": \"/abs.png\"}", status: 400)
                }
                switch scope {
                case "page":
                    guard let tabRaw = payload["tabID"] as? String,
                          let tabID = UUID(uuidString: tabRaw),
                          let found = DebugHarnessRegistry.shared.findTab(tabID),
                          let page = found.tab.browserPage
                    else {
                        return HarnessHTTPResponse.error("page scope needs a valid tabID", status: 404)
                    }
                    let image: NSImage? = await withCheckedContinuation { continuation in
                        page.takeSnapshot(configuration: BrowserSnapshotConfiguration(afterScreenUpdates: true, rect: nil)) { image, _ in
                            continuation.resume(returning: image)
                        }
                    }
                    guard let image else {
                        return HarnessHTTPResponse.error("snapshot failed", status: 500)
                    }
                    return Self.writePNG(image: image, to: path)
                case "window":
                    guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) }),
                          let view = window.contentView,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                    else {
                        return HarnessHTTPResponse.error("no visible window", status: 404)
                    }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    guard let png = rep.representation(using: .png, properties: [:]) else {
                        return HarnessHTTPResponse.error("png encode failed", status: 500)
                    }
                    do {
                        try png.write(to: URL(fileURLWithPath: path))
                    } catch {
                        return HarnessHTTPResponse.error("write failed: \(error.localizedDescription)", status: 500)
                    }
                    return HarnessHTTPResponse.json(["path": path, "width": Int(rep.pixelsWide), "height": Int(rep.pixelsHigh)])
                default:
                    return HarnessHTTPResponse.error("scope must be page or window", status: 400)
                }
```

Add the shared PNG writer inside the enum:

```swift
        static func writePNG(image: NSImage, to path: String) -> HarnessHTTPResponse {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else {
                return HarnessHTTPResponse.error("png encode failed", status: 500)
            }
            do {
                try png.write(to: URL(fileURLWithPath: path))
                return HarnessHTTPResponse.json(["path": path, "width": Int(rep.pixelsWide), "height": Int(rep.pixelsHigh)])
            } catch {
                return HarnessHTTPResponse.error("write failed: \(error.localizedDescription)", status: 500)
            }
        }
```

Also add `import AppKit` at the top of the file (below `import Foundation`, still inside `#if DEBUG`).

**Implementer note:** check `BrowserSnapshotConfiguration`'s actual initializer in `evo/Core/BrowserEngine/BrowserPage.swift` (or wherever it's defined — `grep -rn "struct BrowserSnapshotConfiguration" evo/`) and match it; the contract is "full-view snapshot after screen updates".

- [ ] **Step 3: Build and verify by hand**

```bash
./scripts/xcbuild-debug.sh && pkill -f "Evo.app/Contents/MacOS/Evo"; open ~/Library/Developer/Xcode/DerivedData/Evo-*/Build/Products/Debug/Evo.app
sleep 3
TOKEN=$(cat ~/Library/Application\ Support/Evo/harness-token)
H="X-Evo-Harness-Token: $TOKEN"
TAB=$(curl -s -H "$H" -X POST -d '{"url":"https://example.com"}' http://127.0.0.1:4590/navigate | python3 -c "import sys,json;print(json.load(sys.stdin)['tabID'])")
sleep 2
curl -s -H "$H" -X POST -d "{\"tabID\":\"$TAB\",\"js\":\"document.title\"}" http://127.0.0.1:4590/eval
curl -s -H "$H" -X POST -d "{\"tabID\":\"$TAB\",\"js\":\"nonexistent.fn()\"}" http://127.0.0.1:4590/eval
curl -s -H "$H" -X POST -d "{\"scope\":\"page\",\"tabID\":\"$TAB\",\"path\":\"/tmp/evo-page.png\"}" http://127.0.0.1:4590/screenshot
curl -s -H "$H" -X POST -d '{"scope":"window","path":"/tmp/evo-window.png"}' http://127.0.0.1:4590/screenshot
file /tmp/evo-page.png /tmp/evo-window.png
```

Expected: eval returns `{"result":"Example Domain"}`; the bad eval returns `jsException: true`; both `file` outputs say `PNG image data` with sane dimensions.

- [ ] **Step 4: Commit**

```bash
git add evo/Core/Services/Debug/DebugHarnessRouter.swift
git commit -m "feat(debug-harness): /eval with timeout and /screenshot (page + window scopes)"
```

---

### Task 7: Autofill routes — /overlay, /keypress, /provider

**Files:**
- Modify: `evo/Core/Services/Debug/DebugHarnessRouter.swift`
- Modify: `evo/Features/Passwords/Services/PasswordAutofillCoordinator.swift:512` (make `handleKeyCommand` internal)

**Interfaces:**
- Consumes: `Tab.passwordOverlayState: PasswordAutofillOverlayState?` (`Tab.swift:54`), `PasswordAutofillOverlayState.suggestions/.focus/.selectedSuggestionIndex` (`PasswordAutofillCoordinator.swift:52-113`), `PasswordAutofillSuggestion` cases (same file, lines 4-49), `Tab.passwordCoordinator: PasswordAutofillCoordinator?` (`Tab.swift:53`), `PasswordAutofillKeyCommand(rawValue:)` (`PasswordBridgeTypes.swift:18`), `SettingsStore.shared.passwordManagerProvider: PasswordManagerProviderKind` (`evo/Core/Utilities/SettingsStore.swift:250`), `PasswordManagerProviderRegistry.shared.activeProvider(for:)`.
- Produces routes:
  - `GET /overlay?tab=<uuid>` → `{visible, fieldID?, fieldKind?, hostname?, selectionIndex?, rows: [{id, label, detail}]}`
  - `POST /keypress` body `{"tabID", "command"}` command ∈ `moveUp|moveDown|activate|dismiss` → `{ok: true}`
  - `GET /provider` → `{kind, state}`; `POST /provider` body `{"kind"}` → `{ok: true}`

- [ ] **Step 1: Make handleKeyCommand callable**

In `evo/Features/Passwords/Services/PasswordAutofillCoordinator.swift:512`, change:

```swift
    private func handleKeyCommand(_ command: PasswordAutofillKeyCommand) {
```

to:

```swift
    func handleKeyCommand(_ command: PasswordAutofillKeyCommand) {
```

- [ ] **Step 2: Add the overlay route**

In `DebugHarnessRouter.swift` add:

```swift
            case ("GET", "/overlay"):
                guard let tabRaw = request.query["tab"], let tabID = UUID(uuidString: tabRaw) else {
                    return HarnessHTTPResponse.error("query must include ?tab=<uuid>", status: 400)
                }
                guard let found = DebugHarnessRegistry.shared.findTab(tabID) else {
                    return HarnessHTTPResponse.error("unknown tab", status: 404)
                }
                guard let overlay = found.tab.passwordOverlayState else {
                    return HarnessHTTPResponse.json(["visible": false, "rows": [[String: Any]]()])
                }
                let rows: [[String: Any]] = overlay.suggestions.map { suggestion in
                    let (label, detail): (String, String)
                    switch suggestion {
                    case let .generatedPassword(host, _):
                        (label, detail) = ("Generated password", host)
                    case let .savedCredential(credential):
                        (label, detail) = (credential.title, credential.displayUsername)
                    case let .email(emailSuggestion):
                        (label, detail) = (emailSuggestion.email, "email")
                    case let .unlockProvider(providerLabel):
                        (label, detail) = ("Unlock \(providerLabel)", "locked")
                    case let .fillOneTimeCode(credential):
                        (label, detail) = ("One-time code", credential.displayUsername)
                    case let .fillCard(item):
                        (label, detail) = (item.title, item.subtitle)
                    case let .fillIdentity(item):
                        (label, detail) = (item.title, item.subtitle)
                    }
                    return ["id": suggestion.id, "label": label, "detail": detail]
                }
                return HarnessHTTPResponse.json([
                    "visible": true,
                    "fieldID": overlay.focus.fieldID,
                    "fieldKind": overlay.focus.fieldKind.rawValue,
                    "hostname": overlay.focus.hostname,
                    "selectionIndex": overlay.selectedSuggestionIndex,
                    "rows": rows,
                ])
```

**Implementer note:** `PasswordAutofillFieldKind` — confirm it's `RawRepresentable` with a `String` raw value (`PasswordBridgeTypes.swift`); if not, use `String(describing:)`.

- [ ] **Step 3: Add keypress and provider routes**

```swift
            case ("POST", "/keypress"):
                guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                      let tabRaw = payload["tabID"] as? String,
                      let tabID = UUID(uuidString: tabRaw),
                      let commandRaw = payload["command"] as? String,
                      let command = PasswordAutofillKeyCommand(rawValue: commandRaw)
                else {
                    return HarnessHTTPResponse.error("body must be {\"tabID\", \"command\": moveUp|moveDown|activate|dismiss}", status: 400)
                }
                guard let found = DebugHarnessRegistry.shared.findTab(tabID),
                      let coordinator = found.tab.passwordCoordinator
                else {
                    return HarnessHTTPResponse.error("unknown tab or no coordinator", status: 404)
                }
                coordinator.handleKeyCommand(command)
                return HarnessHTTPResponse.json(["ok": true])

            case ("GET", "/provider"):
                let kind = SettingsStore.shared.passwordManagerProvider
                let provider = PasswordManagerProviderRegistry.shared.activeProvider(for: kind)
                return HarnessHTTPResponse.json([
                    "kind": kind.rawValue,
                    "state": String(describing: provider.state),
                ])

            case ("POST", "/provider"):
                guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                      let kindRaw = payload["kind"] as? String,
                      let kind = PasswordManagerProviderKind(rawValue: kindRaw)
                else {
                    return HarnessHTTPResponse.error("body must be {\"kind\": evo|onePassword|mock}", status: 400)
                }
                SettingsStore.shared.passwordManagerProvider = kind
                return HarnessHTTPResponse.json(["ok": true])
```

- [ ] **Step 4: Build and verify by hand (real overlay against a live page)**

```bash
./scripts/xcbuild-debug.sh && pkill -f "Evo.app/Contents/MacOS/Evo"; open ~/Library/Developer/Xcode/DerivedData/Evo-*/Build/Products/Debug/Evo.app
sleep 3
TOKEN=$(cat ~/Library/Application\ Support/Evo/harness-token)
H="X-Evo-Harness-Token: $TOKEN"
curl -s -H "$H" -X POST -d '{"kind":"mock"}' http://127.0.0.1:4590/provider
curl -s -H "$H" http://127.0.0.1:4590/provider
```

Expected: `{"ok":true}` then `{"kind":"mock","state":"ready"}`. Full overlay verification lands in Task 9 once fixtures exist (needs a page with a login form on 127.0.0.1).

- [ ] **Step 5: Commit**

```bash
git add evo/Core/Services/Debug/DebugHarnessRouter.swift evo/Features/Passwords/Services/PasswordAutofillCoordinator.swift
git commit -m "feat(debug-harness): /overlay, /keypress, /provider routes"
```

---

### Task 8: Fixtures and fixture server

**Files:**
- Create: `fixtures/login-basic.html`, `fixtures/login-two-step.html`, `fixtures/signup.html`, `fixtures/change-password.html`, `fixtures/card-checkout.html`, `fixtures/identity-form.html`, `fixtures/otp.html`
- Create: `scripts/fixture-server.py`

**Interfaces:**
- Consumes: nothing from the app.
- Produces: static pages on `http://127.0.0.1:4599/<name>.html`, plus `GET /basic-auth` (HTTP Basic 401 challenge, accepts `alice@example.com` / `correct-horse-battery-staple`) and `GET /digest-auth` (Digest MD5 challenge, same credentials). Every form has stable element IDs (listed per page below) for `/eval` assertions.

- [ ] **Step 1: Write the fixture pages**

`fixtures/login-basic.html` (IDs: `username`, `password`, `submit`, `status`):

```html
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Fixture: Basic Login</title></head>
<body>
<h1>Basic Login</h1>
<form id="login-form">
    <label>Email <input type="email" id="username" name="username" autocomplete="username"></label>
    <label>Password <input type="password" id="password" name="password" autocomplete="current-password"></label>
    <button type="submit" id="submit">Sign in</button>
</form>
<p id="status">signed-out</p>
<script>
    document.getElementById("login-form").addEventListener("submit", (event) => {
        event.preventDefault();
        document.getElementById("status").textContent =
            "submitted:" + document.getElementById("username").value;
    });
</script>
</body>
</html>
```

`fixtures/login-two-step.html` — the Google-style gap: page 1 has ONLY a username field; the password field appears after Next (IDs: `username`, `next`, `password`, `submit`, `status`):

```html
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Fixture: Two-Step Login</title></head>
<body>
<h1>Two-Step Login</h1>
<div id="step1">
    <label>Email <input type="email" id="username" name="username" autocomplete="username"></label>
    <button type="button" id="next">Next</button>
</div>
<div id="step2" hidden>
    <label>Password <input type="password" id="password" name="password" autocomplete="current-password"></label>
    <button type="button" id="submit">Sign in</button>
</div>
<p id="status">step-1</p>
<script>
    document.getElementById("next").addEventListener("click", () => {
        document.getElementById("step1").hidden = true;
        document.getElementById("step2").hidden = false;
        document.getElementById("status").textContent = "step-2";
        document.getElementById("password").focus();
    });
    document.getElementById("submit").addEventListener("click", () => {
        document.getElementById("status").textContent =
            "submitted:" + document.getElementById("username").value;
    });
</script>
</body>
</html>
```

`fixtures/signup.html` (IDs: `username`, `new-password`, `confirm-password`, `submit`, `status`):

```html
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Fixture: Signup</title></head>
<body>
<h1>Create Account</h1>
<form id="signup-form">
    <label>Email <input type="email" id="username" name="email" autocomplete="username"></label>
    <label>Password <input type="password" id="new-password" name="new-password" autocomplete="new-password"></label>
    <label>Confirm <input type="password" id="confirm-password" name="confirm-password" autocomplete="new-password"></label>
    <button type="submit" id="submit">Create</button>
</form>
<p id="status">unregistered</p>
<script>
    document.getElementById("signup-form").addEventListener("submit", (event) => {
        event.preventDefault();
        document.getElementById("status").textContent = "registered";
    });
</script>
</body>
</html>
```

`fixtures/change-password.html` (IDs: `current-password`, `new-password`, `confirm-password`, `submit`, `status`):

```html
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Fixture: Change Password</title></head>
<body>
<h1>Change Password</h1>
<form id="change-form">
    <label>Current <input type="password" id="current-password" autocomplete="current-password"></label>
    <label>New <input type="password" id="new-password" autocomplete="new-password"></label>
    <label>Confirm <input type="password" id="confirm-password" autocomplete="new-password"></label>
    <button type="submit" id="submit">Change</button>
</form>
<p id="status">unchanged</p>
<script>
    document.getElementById("change-form").addEventListener("submit", (event) => {
        event.preventDefault();
        document.getElementById("status").textContent = "changed";
    });
</script>
</body>
</html>
```

`fixtures/card-checkout.html` (IDs: `cc-name`, `cc-number`, `cc-exp`, `cc-cvc`, `submit`, `status`):

```html
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Fixture: Checkout</title></head>
<body>
<h1>Checkout</h1>
<form id="checkout-form">
    <label>Name on card <input id="cc-name" autocomplete="cc-name"></label>
    <label>Card number <input id="cc-number" autocomplete="cc-number" inputmode="numeric"></label>
    <label>Expiry <input id="cc-exp" autocomplete="cc-exp" placeholder="MM/YY"></label>
    <label>CVC <input id="cc-cvc" autocomplete="cc-csc" inputmode="numeric"></label>
    <button type="submit" id="submit">Pay</button>
</form>
<p id="status">unpaid</p>
<script>
    document.getElementById("checkout-form").addEventListener("submit", (event) => {
        event.preventDefault();
        document.getElementById("status").textContent = "paid";
    });
</script>
</body>
</html>
```

`fixtures/identity-form.html` (IDs: `given-name`, `family-name`, `address-line1`, `city`, `state`, `postal-code`, `country`, `phone`, `email`, `submit`, `status`):

```html
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Fixture: Shipping Address</title></head>
<body>
<h1>Shipping Address</h1>
<form id="identity-form">
    <label>First name <input id="given-name" autocomplete="given-name"></label>
    <label>Last name <input id="family-name" autocomplete="family-name"></label>
    <label>Address <input id="address-line1" autocomplete="address-line1"></label>
    <label>City <input id="city" autocomplete="address-level2"></label>
    <label>State <input id="state" autocomplete="address-level1"></label>
    <label>ZIP <input id="postal-code" autocomplete="postal-code"></label>
    <label>Country <input id="country" autocomplete="country-name"></label>
    <label>Phone <input id="phone" autocomplete="tel"></label>
    <label>Email <input id="email" autocomplete="email"></label>
    <button type="submit" id="submit">Save</button>
</form>
<p id="status">empty</p>
<script>
    document.getElementById("identity-form").addEventListener("submit", (event) => {
        event.preventDefault();
        document.getElementById("status").textContent = "saved";
    });
</script>
</body>
</html>
```

`fixtures/otp.html` (IDs: `otp`, `submit`, `status`):

```html
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Fixture: One-Time Code</title></head>
<body>
<h1>Enter Code</h1>
<form id="otp-form">
    <label>Code <input id="otp" name="otp" autocomplete="one-time-code" inputmode="numeric"></label>
    <button type="submit" id="submit">Verify</button>
</form>
<p id="status">unverified</p>
<script>
    document.getElementById("otp-form").addEventListener("submit", (event) => {
        event.preventDefault();
        document.getElementById("status").textContent =
            "verified:" + document.getElementById("otp").value;
    });
</script>
</body>
</html>
```

- [ ] **Step 2: Write the fixture server**

Create `scripts/fixture-server.py`:

```python
#!/usr/bin/env python3
"""Serves fixtures/ on 127.0.0.1:4599 plus HTTP Basic and Digest auth challenge routes."""
import base64
import hashlib
import http.server
import os
import secrets
import sys

PORT = 4599
USER = "alice@example.com"
PASSWORD = "correct-horse-battery-staple"
REALM = "evo-fixtures"
FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fixtures")
NONCE = secrets.token_hex(16)

BODY_OK = b"<html><body><h1 id='status'>authorized</h1></body></html>"


def md5(text: str) -> str:
    return hashlib.md5(text.encode()).hexdigest()


class FixtureHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=FIXTURES, **kwargs)

    def do_GET(self):
        if self.path == "/basic-auth":
            return self.handle_basic()
        if self.path == "/digest-auth":
            return self.handle_digest()
        return super().do_GET()

    def handle_basic(self):
        header = self.headers.get("Authorization", "")
        expected = "Basic " + base64.b64encode(f"{USER}:{PASSWORD}".encode()).decode()
        if header == expected:
            return self.respond_ok()
        self.send_response(401)
        self.send_header("WWW-Authenticate", f'Basic realm="{REALM}"')
        self.end_headers()

    def handle_digest(self):
        header = self.headers.get("Authorization", "")
        if header.startswith("Digest ") and self.digest_valid(header):
            return self.respond_ok()
        self.send_response(401)
        self.send_header(
            "WWW-Authenticate",
            f'Digest realm="{REALM}", nonce="{NONCE}", qop="auth", algorithm=MD5',
        )
        self.end_headers()

    def digest_valid(self, header: str) -> bool:
        fields = {}
        for part in header[len("Digest "):].split(","):
            if "=" not in part:
                continue
            key, _, value = part.strip().partition("=")
            fields[key] = value.strip('"')
        ha1 = md5(f"{USER}:{REALM}:{PASSWORD}")
        ha2 = md5(f"GET:{fields.get('uri', '')}")
        if fields.get("qop") == "auth":
            expected = md5(
                f"{ha1}:{fields.get('nonce', '')}:{fields.get('nc', '')}:"
                f"{fields.get('cnonce', '')}:auth:{ha2}"
            )
        else:
            expected = md5(f"{ha1}:{fields.get('nonce', '')}:{ha2}")
        return fields.get("response") == expected

    def respond_ok(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(BODY_OK)))
        self.end_headers()
        self.wfile.write(BODY_OK)

    def log_message(self, fmt, *args):
        print(f"[fixture-server] {fmt % args}", file=sys.stderr)


if __name__ == "__main__":
    with http.server.ThreadingHTTPServer(("127.0.0.1", PORT), FixtureHandler) as server:
        print(f"[fixture-server] http://127.0.0.1:{PORT}/ serving {FIXTURES}", file=sys.stderr)
        server.serve_forever()
```

- [ ] **Step 3: Verify the fixture server standalone**

```bash
chmod +x scripts/fixture-server.py
python3 scripts/fixture-server.py &
sleep 1
curl -s http://127.0.0.1:4599/login-basic.html | grep -c "login-form"
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:4599/basic-auth
curl -s -o /dev/null -w "%{http_code}\n" -u "alice@example.com:correct-horse-battery-staple" http://127.0.0.1:4599/basic-auth
curl -s -o /dev/null -w "%{http_code}\n" --digest -u "alice@example.com:correct-horse-battery-staple" http://127.0.0.1:4599/digest-auth
kill %1
```

Expected: `1`, `401`, `200`, `200`.

- [ ] **Step 4: Commit**

```bash
git add fixtures scripts/fixture-server.py
git commit -m "feat(debug-harness): fixture pages and local auth-challenge server"
```

---

### Task 9: End-to-end verification — the full loop

**Files:**
- Create: `scripts/harness-smoke.sh`

**Interfaces:**
- Consumes: everything above.
- Produces: a repeatable smoke script proving the loop from the spec: mock provider → fixture login page → focus → overlay rows → keypress-activate → filled values → screenshots.

- [ ] **Step 1: Write the smoke script**

Create `scripts/harness-smoke.sh`:

```bash
#!/bin/bash
# End-to-end smoke of the debug harness. Requires: debug Evo.app running, fixture server running.
set -euo pipefail

PORT="${EVO_HARNESS_PORT:-4590}"
TOKEN=$(cat "$HOME/Library/Application Support/Evo/harness-token")
BASE="http://127.0.0.1:$PORT"
OUT="${1:-/tmp/evo-harness-smoke}"
mkdir -p "$OUT"

req() { curl -sf -H "X-Evo-Harness-Token: $TOKEN" "$@"; }

echo "1. health"; req "$BASE/health"

echo "2. switch to mock provider"
req -X POST -d '{"kind":"mock"}' "$BASE/provider"

echo "3. open the basic login fixture"
TAB=$(req -X POST -d '{"url":"http://127.0.0.1:4599/login-basic.html"}' "$BASE/navigate" | python3 -c "import sys,json;print(json.load(sys.stdin)['tabID'])")
sleep 2

echo "4. focus the username field"
req -X POST -d "{\"tabID\":\"$TAB\",\"js\":\"document.getElementById('username').focus(); true\"}" "$BASE/eval"
sleep 1

echo "5. overlay state (expect visible with 2 mock rows)"
req "$BASE/overlay?tab=$TAB" | tee "$OUT/overlay.json"

echo "6. screenshot the window with overlay up"
req -X POST -d "{\"scope\":\"window\",\"path\":\"$OUT/overlay.png\"}" "$BASE/screenshot"

echo "7. activate the first suggestion"
req -X POST -d "{\"tabID\":\"$TAB\",\"command\":\"activate\"}" "$BASE/keypress"
sleep 1

echo "8. read filled values (expect alice + password)"
req -X POST -d "{\"tabID\":\"$TAB\",\"js\":\"JSON.stringify({u: document.getElementById('username').value, p: document.getElementById('password').value})\"}" "$BASE/eval" | tee "$OUT/filled.json"

echo "9. screenshot the filled page"
req -X POST -d "{\"scope\":\"page\",\"tabID\":\"$TAB\",\"path\":\"$OUT/filled.png\"}" "$BASE/screenshot"

echo "smoke complete → $OUT"
```

- [ ] **Step 2: Run the loop**

```bash
chmod +x scripts/harness-smoke.sh
python3 scripts/fixture-server.py & FIXPID=$!
pkill -f "Evo.app/Contents/MacOS/Evo" || true
open ~/Library/Developer/Xcode/DerivedData/Evo-*/Build/Products/Debug/Evo.app
sleep 4
./scripts/harness-smoke.sh /tmp/evo-harness-smoke
kill $FIXPID
```

Expected: every step prints without curl failing; `overlay.json` shows `"visible":true` and two rows (`Fixture Site A` / `alice@example.com`, `Fixture Site A (alt)` / `bob@example.com`); `filled.json` shows `alice@example.com` and `correct-horse-battery-staple`; both PNGs exist. If the overlay doesn't appear, debug via `GET /overlay` + window screenshots — that's the harness doing its job; likely causes: JS focus without user gesture not triggering the bridge's focus handler (check `password-manager.js` `handleFocus`), or the mock provider not active.

- [ ] **Step 3: Run the full existing test suite (regression gate)**

```bash
xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **` — nothing pre-existing broke.

- [ ] **Step 4: Lint and format**

```bash
swiftformat evo/Core/Services/Debug evo/Features/Passwords/Providers/MockPasswordProvider.swift evoTests/DebugHarness
swiftlint lint --use-alternative-excluding 2>&1 | grep -E "Debug|Mock" | head
```

Expected: no new violations (no force unwraps were written).

- [ ] **Step 5: Commit**

```bash
git add scripts/harness-smoke.sh
git commit -m "feat(debug-harness): end-to-end smoke script"
```
