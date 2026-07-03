# EvoWork — Features & Functionality Added on Top of OpenWork

> EvoWork is a fork of [OpenWork](https://github.com/different-ai/openwork) (an Electron
> desktop app for agentic work on your own files). This document catalogs everything **we
> added or changed** relative to upstream OpenWork. The fork diverges from upstream at the
> "add Claude Code as a selectable workspace engine" commit; everything below is fork-only
> work.

_Last updated: 2026-06-30. Generated from the `evo/dev` history plus the in-flight
`feat/ms365-session-replay` branch._

---

## 1. Claude Engine — the headline feature

The biggest change: EvoWork ships a **native Claude engine** alongside OpenWork's OpenCode
engine. Instead of calling an SDK, it **spawns the real `claude` CLI as a subprocess** and
speaks its `stream-json` protocol, then translates those events into the OpenCode-shaped
events the existing React UI already understands. This means the same UI renders both
OpenCode and Claude sessions identically.

- **Selectable workspace engine** → then promoted to the **global default engine**, with
  onboarding landing you directly in Chat (no per-workspace engine choice).
- **Real `claude` CLI subprocess** driven over `--output-format stream-json` /
  `--input-format stream-json`, with a protocol adapter that maps Claude events onto
  OpenCode's message/part model.
- **One process per session** so conversation context persists across turns; **one stable
  session identity** so sessions stop merging or disappearing.
- **Session history in the sidebar** — surface existing `claude` CLI sessions with view +
  resume, including in the "View all sessions" browser. (Note: `~/.claude/projects` history
  is shared with the real CLI and across dev/prod.)
- **Archive / Rename / Delete** work for Claude sessions; archived sessions close their tab.
- **Interactive prompts** — `AskUserQuestion` wired end-to-end so the model can ask the user
  an answerable multiple-choice question inside the chat.
- **Rich tool rendering** — every out-of-the-box Claude tool renders with a clear label +
  icon; resumed tool calls render as expandable parts; pasted/attached images render in
  history (not "[image]").
- **Image input** — pasted/attached images are forwarded to the Claude engine.
- **Live date/time injection** — the current date/time is injected on every turn so the
  model isn't stuck at its training cutoff.
- **Slash-command persistence** — the `/` command menu survives a cold start.
- **Engine isolation** — OpenCode-only boot/reload machinery is gated and skipped when the
  Claude engine is active (no OpenCode server scaffolding for Claude workspaces).

## 2. Always-on Browser MCP (for the Claude engine)

A bundled MCP server that gives Claude a controllable browser inside EvoWork.

- **Bridge tools**: `open_url`, set/clear proxy, plus the re-exposed
  `opencode-chrome-devtools` CDP verbs (navigation, evaluation, snapshots).
- **"Let Claude use the browser" toggle** in Settings, **default on**; the preference is
  threaded into the engine start payload and a managed MCP config is written per launch.
- **Prod delivery via bundling** (esbuild → app Resources) rather than npm publish — so
  updating it means rebuilding the app.
- Forces a fresh page read after a sign-in handoff so the model sees post-login state.

## 3. Microsoft 365 integration

Two generations of M365 support:

**a) M365 Graph MCP (device-code auth)**
- MCP server exposing **Mail** (list/search/read), **Calendar**, **Presence**, and **Teams
  chat** (list/read/send) tools over Microsoft Graph.
- **Device-code auth flow** with a token broker on the UI-control server, tokens stored via
  Electron `safeStorage` (plaintext fallback in dev).
- **Settings → Extensions → Microsoft 365** config panel + catalog entry; MCP injection into
  Claude is gated on the extension (default on) and reflects connection state in the card.
- **Microsoft To Do** tasks were added, then **shelved** — the AT&T tenant blocks
  `Tasks.ReadWrite` consent.

**b) M365 Session-Replay (in-flight — `feat/ms365-session-replay`)**
A pivot away from Graph (AT&T blocks new app consent) toward **read-only Outlook/Teams via
in-page `fetch` inside EvoWork's own embedded browser**, reusing the shared browser session:
- Production **WebContentsView worker factory** and **host lifecycle**.
- **Session route table** on the UI-control server (signed-out + drift handling) with a
  Teams chats adapter that normalizes results.
- **Outlook + Teams shortcut icons** in the right rail.

## 4. OpenWork Cloud (Den) removal — fully local

EvoWork strips the upstream multi-tenant cloud stack to run **local-only**:
- Removed the entire `ee/` **Den backend** (Hono/Drizzle/MySQL/Better-Auth/Stripe) and its
  infra/scripts/config.
- Removed **remote workspaces**, desktop Den bootstrap, sign-in plumbing, and the renderer
  cloud domain / OpenWork Models / sign-in UI.
- Removed **all analytics/telemetry** (PostHog + Den telemetry, the pref, and the toggle).
- Added a **local permissive restriction shim** in place of Den-driven policy, and repointed
  call sites. (The Claude plugin install path was intentionally kept.)

## 5. Home (Chat) space

- A **synthetic "Home / Chat" workspace** composed at bootstrap, **pinned first** in the
  sidebar, that the app **lands in on launch**.
- Home skips OpenCode activation/reconnect and is excluded from workspace-count gates, so it
  behaves like a lightweight always-there chat surface.

## 6. Dev-instance ergonomics

- `pnpm dev` / `pnpm dev:onboarding` scripts with **clean-slate reset** — wipe the dev
  Electron profile + dev data dir at boot (window position preserved), auto-skip onboarding
  on a freshly-wiped profile.
- **DEV badge + caution-tape status bar** so a dev build is never mistaken for prod.
- **Window-state persistence** (bounds restored across launches).
- Dev state isolated from real config (`~/.openwork/...-dev`).

## 7. UX / composer / sidebar / observability polish

**Composer**
- **Morphing send ⇄ stop** icon button (Claude-Code style); **Stop** stays visible for the
  whole run.
- **Live elapsed-time + spinner** while the agent works.

**Sidebar & sessions**
- **View-all-sessions browser** with **bulk archive** and a visible bulk-archive bar.
- Explicit workspace **name asc/desc sort**, **collapse-all / expand-all** toggle.
- Persistent **leading status icon** on session rows; several indent/spacing refinements;
  fixed accidental workspace reorder on click; archived sessions grouped at the bottom.
- Reliable **scroll-to-latest** on session open; selectable text in user messages.

**Status bar & debugging**
- **Live Claude usage pill**; **running-subagents** indicator with hover detail (removed the
  upstream Docs/Feedback items).
- In-app **debug panel** with **session-log export** and **pino-style JSON coloring** + word
  wrap.

**Computer Use / permissions**
- Multiple fixes so the macOS permission GUI opens even when the MCP helper runs, a single
  source of truth for permission state, live-refresh on window focus, and correct TCC
  responsibility handling.

**Branding & housekeeping**
- Rename the Computer Use helper to **EvoWork** (display only); removed upstream OpenWork
  GitHub Actions workflows; gitignore local code-signing certs/keys.

---

### Architecture recap (how the Claude engine fits)

```
apps/app (React renderer + web UI)
   │  @opencode-ai/sdk client, IPC fetch bridge in Electron
   ▼
apps/desktop (Electron shell)
   ├─ OpenCode engine (default upstream): RuntimeManager → opencode serve / orchestrator
   └─ Claude engine (EvoWork):
        electron/claude/spawn-claude.mjs → spawns real `claude` CLI (stream-json)
        electron/claude/translate-to-opencode.mjs → adapts Claude protocol → OpenCode events
        electron/claude/sessions.mjs → session lifecycle / transcripts
        + bundled Browser MCP and M365 MCP injected via --mcp-config
```

Both engines present the **same OpenCode-shaped protocol** to the renderer, which is why one
UI transparently renders OpenCode and Claude sessions alike.
