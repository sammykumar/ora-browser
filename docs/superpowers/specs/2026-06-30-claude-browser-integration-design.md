# Claude-in-the-Browser — Design

_Status: approved (design). Date: 2026-06-30._

## What this is

Make Evo the place where Sam talks to Claude, so the browser — not a separate
app — is the hub between Claude Code, VS Code, and the web. Evo gains an
always-available Claude surface backed by a **real Claude Code agent loop** that
can see and act on the pages already open (with their live cookies/auth), reach
local dev MCP servers, spawn sessions in local repos, use 1Password credentials,
and eventually be driven remotely.

This mirrors what **EvoWork** (a fork of [OpenWork](https://github.com/different-ai/openwork))
already proved in Electron: spawn the real `claude` CLI as a subprocess, speak
its `stream-json` protocol, and render it in a native UI. Evo re-does that
natively in Swift — but with an inversion: in EvoWork the browser was a tool the
CLI drove; here **the browser is the host app and must expose its own WKWebViews
_to_ Claude.**

## Engine decision (settled)

**Claude runs as the real `claude` CLI spawned as a subprocess.** Swift launches
`claude` in streaming-JSON mode, parses the event stream, and renders it in native
SwiftUI. This inherits all of Claude Code for free — tool use, MCP clients,
local-repo sessions, `~/.claude/projects` history, subagents, permissions — and is
the fastest path to the full vision.

Rejected alternatives: (a) Anthropic Swift SDK / Messages API directly —
reimplements the agent loop, MCP client, sessions, and "session in my repo" has
no built-in meaning; (b) Claude Agent SDK as a Node/Python sidecar — closer to
EvoWork's shape but adds a non-Swift sidecar to bundle.

Consequence for CLAUDE.md's "Swift MCP SDK" priority: the Swift MCP SDK is how Evo
**serves** browser tools to the CLI, not how it reimplements the client.

## Decomposition — the pillars

The full vision is too big for one spec. It decomposes into pillars hanging off a
single spine (Pillar 0). Each pillar gets its own spec → plan → build cycle.

- **Pillar 0 — Claude Engine Host (Swift core).** Spawn `claude` in stream-json
  mode, one process per session, parse events into a native model, manage
  lifecycle, own session identity/persistence (shared `~/.claude/projects`).
  Everything depends on this.
- **Pillar 1 — Chat rendering + the 3 surfaces.** Message list, streaming,
  tool-call rendering, composer (morphing send/stop, elapsed timer), inline
  `AskUserQuestion`, image input. Plus the surface abstraction: **side panel**,
  **dedicated Chat space** (EvoWork's Home/Chat model), and **launcher/command-bar
  overlay** — three views bound to one engine. Depends on 0.
- **Pillar 2 — Browser vision + control.** Evo runs an MCP server exposing tools
  over its own WKWebViews: read/snapshot current or any tab; navigate/click/fill/
  scroll/evaluate; list tabs & spaces. Driving in-app WebViews **inherits live
  cookies/auth for free** — the "reuse my existing auth" requirement satisfied
  structurally. Depends on 0.
- **Pillar 3 — Native 1Password integration.** A first-class 1Password config
  panel in Settings (connect / status / expose-to-Claude toggle, in the shape of
  EvoWork's M365 extension card). Once connected, Claude fetches secrets and
  autofills logins via the browser-control tools, without secrets living in
  prompts. Likely mechanism: the `op` CLI with 1Password desktop-app biometric
  unlock (Touch ID gates each access), exposed to Claude as its own MCP server so
  every credential fetch is an auditable tool call. Exact mechanism finalized when
  Pillar 3 is spec'd. Depends on 2.
- **Pillar 4 — Local-repo sessions.** Spawn `claude` with cwd set to a chosen git
  repo; repo picker; per-repo session history. Mostly "configure subprocess cwd +
  a picker" once 0 exists. Depends on 0.
- **Pillar 5 — Remote surface.** Drive Evo from a phone + trigger sessions when
  away + notifications — a relay/companion talking to the running engine host.
  ("Claude controls remote machines" mostly falls out of the CLI's own bash/ssh/
  MCP reach, so it's near-free once 0 exists; the phone-driving and unattended-
  trigger parts are the real work.) Depends on 0 + a transport.

### Dependency spine

```
        ┌─> Pillar 1 (surfaces)      ┐
        │                            │
Pillar 0├─> Pillar 2 (browser MCP) ──┼─> Pillar 3 (1Password)
(engine)│                            │
        ├─> Pillar 4 (repo sessions) ┘
        └─> Pillar 5 (remote surface)
```

All three Pillar-1 surfaces are views onto one shared engine + session model. Get
that separation right once and side panel, Chat space, and launcher overlay each
become a thin view — usable independently or together.

---

## Sub-project #1 — Walking skeleton: "read-only Claude side panel"

A thin vertical slice through Pillars 0 + 1 + 2 that proves the whole concept
end-to-end, so every later pillar extends a proven seam instead of an unknown.

**Definition of done:** open a page, type in the side panel, and Claude reads the
page you're looking at and responds — with its browser access running through
Evo's own authenticated WebView.

### Architecture

Organizing principle: the CLI subprocess and the browser-tool server are app-wide
singletons; the chat UI state is window-scoped — matching Evo's existing split
(`BrowserEngine.shared` singleton vs. per-window `TabManager`).

```
┌──────────────────── Evo (one process) ─────────────────────┐
│  ClaudeEngine.shared            EvoToolServer.shared        │
│  (spawns `claude` CLI,          (in-process MCP server,     │
│   one Process per session,       127.0.0.1:<port>,          │
│   stream-json over stdio)        Swift MCP SDK)             │
│        │  ▲                            │  ▲                 │
│        │  │ stream-json events         │  │ read_current_page│
│        ▼  │                            ▼  │                 │
│  ┌───────────────┐             @MainActor → TabManager      │
│  │ claude (subproc)│──HTTP MCP──▶ .activeTab.evaluateJS(    │
│  └───────────────┘             "document.body.innerText")   │
│        │                                                    │
│        ▼ AsyncStream<ClaudeEvent>                           │
│  ClaudeChatManager (per-window @MainActor ObservableObject) │
│        ▼                                                    │
│  ClaudeSidePanelView  ── nested HSplit in BrowserSplitView  │
└─────────────────────────────────────────────────────────────┘
```

**Why an HTTP MCP server, not stdio:** the tool must touch live in-process
WebViews, so the server lives *inside* Evo and the `claude` subprocess connects
*out* to `127.0.0.1:<port>` via a generated `--mcp-config`. A stdio server (which
`claude` would spawn as a child) can't see Evo's WebViews. This is the load-bearing
seam the whole vision rests on, so slice #1 proves it for real rather than faking
page-context injection.

### Components (with the seams they build on)

1. **`ClaudeEngine.shared`** — `evo/Core/Claude/`, singleton like
   `BrowserEngine` (`evo/Core/BrowserEngine/BrowserEngine.swift:42`). Spawns
   `claude` in streaming-JSON mode via `Foundation.Process`, one persistent
   process per session so context survives turns. Writes user turns to stdin as
   JSON lines; reads stdout line-by-line into a typed `ClaudeEvent`; exposes an
   `AsyncStream<ClaudeEvent>` per session. Lifecycle: start, send, interrupt
   (stop), teardown. Native analog of EvoWork's `spawn-claude` + `translate` +
   `sessions`, targeting our own model rather than OpenCode's.

2. **`EvoToolServer.shared`** — `evo/Core/Claude/MCP/`, singleton, built on the
   Swift MCP SDK (`modelcontextprotocol/swift-sdk`, new SPM dep alongside the
   existing Sparkle/Inject/FaviconFinder/SafariConverterLib in `project.yml`).
   Binds an ephemeral localhost port; exposes exactly one tool
   `read_current_page`. Handler hops to `@MainActor`, resolves the **frontmost
   window's** `TabManager.activeTab` (`evo/Features/Tabs/State/TabManager.swift:38`),
   runs `document.body.innerText` via `evaluateJavaScript`
   (`evo/Core/BrowserEngine/BrowserPage.swift:154`; per-tab entry
   `evo/Features/Tabs/Models/Tab.swift:373`) wrapped in `withCheckedContinuation`
   (the codebase is completion-handler based today), and returns the text.
   Auth-free by construction — it is the user's real logged-in tab.

3. **`ClaudeChatManager`** — `evo/Features/Claude/State/`, per-window
   `@MainActor ObservableObject`, created in `EvoRoot.init`
   (`evo/App/EvoRoot.swift:35`) and injected via `.environmentObject`
   (`EvoRoot.swift:90`), mirroring `TabManager`/`SidebarManager`. Binds a
   `ClaudeEngine` session, consumes its `AsyncStream`, maintains `@Published
   messages` + running state, exposes `send()` / `stop()`.

4. **`ClaudeSidePanelView` + `ClaudePanelManager`** — `evo/Features/Claude/Views/`.
   Renders messages, streaming assistant text, tool-call rows
   (`▸ read_current_page`), composer with morphing send/stop. Docked via a
   **nested `HSplit` inside `contentView()`** in
   `evo/Features/Browser/Views/BrowserSplitView.swift:78` (web content left,
   Claude right, draggable divider). `ClaudePanelManager` mirrors
   `SidebarManager`'s `FractionHolder`/`SideHolder` and a hotkey toggle. Panel
   chrome/insets follow `evo/Features/Browser/Views/BrowserContentContainer.swift:28`.

### Data flow (one turn)

User types → `ClaudeChatManager.send` → stream-json user message to session stdin
→ `claude` runs → *(optional)* calls `read_current_page` → HTTP to
`EvoToolServer` → `@MainActor` → active tab `innerText` → tool result back →
`claude` streams assistant text + tool events on stdout → `ClaudeEngine` parses
lines to `ClaudeEvent`s → `AsyncStream` → manager updates `@Published messages` →
SwiftUI re-renders incrementally. Stop interrupts the current turn.

### Error handling

- **`claude` not found** (not installed, or wrong PATH) → detect at spawn; show a
  clear panel error with the resolved path + a Settings override field. (Debug
  build is un-sandboxed so spawning works; see open decisions on sandbox/release.)
- **Subprocess crash / non-zero exit** → mark session errored, surface in panel,
  offer restart.
- **Tool errors** (no active tab, JS eval fails/times out) → return a structured
  MCP tool error so `claude` can recover; log it.
- **Malformed stdout line** → skip + log; never crash the reader.
- **Port bind failure** → retry with a new ephemeral port.

### Testing

- **Stream-json parser** (highest value, pure logic): decode captured real-`claude`
  fixture lines — assistant text, `tool_use`, `tool_result`, `result`/usage,
  error, and split/partial lines. Uses the repo's Swift Testing (`import Testing`)
  style — plain `struct` suites, `@testable import Evo`.
- **`read_current_page` handler**: against a mock active-tab text provider —
  returns text, handles no-tab, handles eval error.
- **Integration (gated on the `claude` binary being present**, like the xcodebuild
  single-test note): spawn real `claude`, one turn, assert a response.
- Views: manual verification (open page → ask → Claude reads it).

### Out of scope for slice #1

Click/fill/navigate control · the Chat space & launcher surfaces · 1Password ·
repo picker (session cwd defaults to a configurable dir, default `~`) · remote/
phone · session-history browser (sessions still persist to `~/.claude/projects`
for free) · sandbox/release build story (debug-only).

### Open decisions (defaults chosen unless revisited)

1. **⚠️ Primary risk — MCP HTTP server transport in the Swift SDK.** The official
   `swift-sdk` has solid client + stdio support; its HTTP/SSE **server** transport
   is the piece to verify. **Plan step 1 is a spike to confirm it.** Fallback if
   not viable: a small `Network.framework` listener speaking MCP Streamable HTTP.
   We keep the MCP seam rather than fake page-context injection, because that seam
   is the whole point.
2. **Session working directory** — a single configurable dir in Settings,
   default `~`. Real repo picker is Pillar 4.
3. **`claude` binary resolution** — auto-detect via login-shell PATH, with a
   Settings override field.
4. **"Current page" = frontmost window's active tab** — `TabManager` is
   per-window, so the tool server tracks the frontmost window.

### Build/sandbox note

`evo.entitlements` enables App Sandbox (blocks spawning arbitrary executables);
`evo-debug.entitlements` does not. Slice #1 targets the **debug daily-driver**
(the primary local-dev path). A sandboxed release can't spawn `claude`; the clean
answer for this personal, non-App-Store tool is a Developer ID (un-sandboxed)
build — deferred, not solved here.

## References

- EvoWork feature catalog: `docs/superpowers/plans/evowork-features.md`
- Existing AI seam (URL shortcuts to replace): `SearchEngine` entries with
  `isAIChat: true` in `evo/Features/Search/Services/SearchEngineService.swift`;
  launcher "Ask …" suggestions in
  `evo/Features/Launcher/State/LauncherViewModel.swift:99`.
