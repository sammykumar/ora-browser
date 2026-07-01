# Evo Browser Roadmap

Evo is a personal, single-user Arc replacement for macOS. This roadmap covers what makes Evo different: AI-aware browsing with MCP integration. Core browsing capabilities that already work (Spaces, vertical tabs, private browsing, password autofill, etc.) are not duplicated here.

## Thesis

The differentiating feature is **AI that can act on pages and reach local tools via MCP**. Anthropic's Swift MCP SDK is the integration vehicle and Claude is the primary model. AI work is prioritized over polish on capabilities that already exist.

## 6-Month Horizon — AI / MCP

Phased so each step is usable on its own and unblocks the next. Phase 1 is the foundation; the order of Phases 2–4 is not yet locked.

### Phase 1 — MCP tool runner (foundation)

The minimum surface everything else builds on.

- Provider abstraction: replace the hardcoded Grok / ChatGPT URL shortcuts (currently in `evo/Features/Launcher/` and `evo/Features/Search/`) with a proper provider layer
- Claude API as the first provider, BYO key
- MCP client via Anthropic's Swift MCP SDK
- Settings UI to wire up MCP servers, with local dev-project servers as the first target
- Minimal chat surface that can invoke MCP tools
- **First win:** connect Evo to a local dev project's MCP server and have Claude operate on it from inside the browser

### Phase 2 — Conversational sidebar

- Persistent chat panel with current-page context
- MCP tools available from the sidebar
- Conversation scoping (per-tab vs per-space vs global) — TBD

### Phase 3 — Command-bar AI

- Extend the existing launcher to route prompts to Claude
- One-shot AI answers and actions from the command bar

### Phase 4 — Agentic page actions

- Primitives for Claude to read the DOM, click, type, and navigate under user control
- Builds on the page-context plumbing from Phase 2 and the MCP runner from Phase 1

## Non-AI Roadmap

Status as of this update — still being triaged.

**Still on the table**

- Split view (two tabs side-by-side in one window)
- Peek (modal-ish quick view before committing to a tab)
- Air Traffic Control (URL routing rules — e.g. work URLs auto-open in the Work space)
- Tab / Space management ergonomics
- Apple-ecosystem integration: Handoff, CloudKit sync, App Intents, Spotlight
- Browser hygiene: Sparkle replacement decision, reader mode via bundled Readability.js

**Cut**

- Little Arc (quick-popup window)
- Boosts (per-site CSS/JS overrides)
- Ad / tracker blocking — Pi-hole at DNS covers it

**Deprioritized**

- Extensions (`WKWebExtension`) — may revisit if a specific need appears
- Cross-platform (Windows / Linux / Android) — ruled out early; see [CLAUDE.md](CLAUDE.md#decisions-already-made--dont-re-litigate)
- iOS / iPadOS port — tractable future direction, not active

_Last updated: 2026-05-24_
