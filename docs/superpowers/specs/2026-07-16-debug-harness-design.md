# Evo Debug Harness — Design

**Date:** 2026-07-16
**Branch:** `debug-harness` (off `passkey-support`)
**Status:** Approved design, pre-implementation

## Problem

Verifying browser features — especially password autofill — currently requires Sam to manually drive the app against real sites with real credentials. That loop is slow, non-reproducible, and puts Sam in the debugging loop instead of at the end of it. The 1Password integration (~6,500 lines shipped) surfaced this: bugs like "username-only pages don't autofill" were found in UAT because there was no way for Claude to exercise the feature first.

## Goal

In Debug builds, Claude can drive and observe evo end-to-end — navigate, inject JS, trigger the autofill overlay, send key commands, read native overlay state, capture screenshots — and verify features against deterministic local fixtures. Sam's role shrinks to one Touch ID-gated UAT pass on the real 1Password path per release.

## Non-goals

- Not compiled into Release builds (hard `#if DEBUG` gate on every piece).
- Not the durable agent-facing MCP server from the agent-consolidation vision. Route handlers are written so an MCP server can wrap them later, but transport, permissions, and multi-session design are explicitly deferred.
- No automation of real secrets. Automated tests run against `MockPasswordProvider` only; the real 1Password sidecar path stays manual (DesktopAuth/Touch ID cannot and should not be scripted).
- No fixes to the known autofill bugs themselves (username-only pages, unlock row). Those are follow-up work that this harness unblocks.

## Architecture

Four components, roughly 700 lines of Swift plus fixture HTML.

### DebugHarnessServer

`evo/Core/Services/Debug/DebugHarnessServer.swift`, wrapped entirely in `#if DEBUG`.

- HTTP server on `NWListener` (Network.framework — no new dependencies), bound to `127.0.0.1` only.
- Port from `EVO_HARNESS_PORT` env var, default 4590.
- Auth: a per-launch random token written to `~/Library/Application Support/Evo/harness-token` with 0600 permissions. Every request must carry it in an `X-Evo-Harness-Token` header; mismatch → 401.
- Started from `AppDelegate.applicationDidFinishLaunching`, alongside the existing Inject hot-reload hook.
- All state access hops to `@MainActor`; the server serializes request handling (one at a time is fine for a test harness).

### DebugHarnessRegistry

Managers (`TabManager` etc.) are per-window `@StateObject`s constructed in `EvoRoot`, so a singleton server cannot reach them directly. `DebugHarnessRegistry` is a Debug-only singleton holding weak references `windowID → TabManager`. `EvoRoot.onAppear` registers; `onDisappear` deregisters — mirroring the existing NotificationCenter-observer pattern documented in CLAUDE.md.

### MockPasswordProvider

- New `PasswordManagerProviderKind` case `mock`, with `isAvailable` false outside Debug and hidden from the Release settings UI.
- Implements the existing 8-requirement `PasswordProvider` protocol (`evo/Features/Passwords/Providers/PasswordProvider.swift`).
- Deterministic in-memory vault: three logins across the two fixture hosts (one with TOTP), one credit card, one identity. Values are fixed constants so assertions are stable.
- Pure and synchronous where the protocol allows — directly unit-testable without the server.

### Fixtures

- `fixtures/` directory at repo root (never bundled into the app).
- `scripts/fixture-server.py` (~60 lines, Python stdlib only): serves the static pages plus live `401` challenge routes for HTTP Basic and Digest auth.
- Pages, one per form shape that has produced bugs: `login-basic.html`, `login-two-step.html` (username-only page → password page, the known Google-style gap), `signup.html`, `change-password.html`, `card-checkout.html`, `identity-form.html`, `otp.html`.

## Route surface (v1)

All responses JSON unless noted. Errors: `{"error": "..."}` with a real HTTP status (400 bad request, 401 bad token, 404 unknown tab/window, 504 eval timeout).

| Method + path | Request | Response |
|---|---|---|
| `GET /health` | — | `{ok, version, pid}` |
| `GET /windows` | — | `[{windowID, isPrivate, tabCount}]` |
| `GET /tabs?window=` | — | `[{tabID, url, title, isActive}]` |
| `POST /navigate` | `{url, tabID?}` — omit tabID for new tab | `{tabID}` |
| `POST /eval` | `{tabID, js}` | `{result}` — JSON-encoded eval result; 5s timeout |
| `GET /overlay?tab=` | — | `{visible, kind, rows: [{title, username, accountLabel}], selectionIndex, anchorRect}` serialized from `Tab.passwordOverlayState` |
| `POST /keypress` | `{tabID, command}` — one of `moveUp/moveDown/activate/dismiss` | `{ok}` — routed through the existing `PasswordAutofillKeyCommand` path |
| `GET /provider` | — | `{kind, state}` |
| `POST /provider` | `{kind}` — `mock`, `evo`, or `onePassword` | `{ok}` |
| `POST /screenshot` | `{scope: "page"\|"window", tabID?, path}` | `{path, width, height}` — PNG written to caller-supplied path |

Screenshot implementation: `scope: page` uses `WKWebView.takeSnapshot(with:)`; `scope: window` renders the window's content view via `bitmapImageRepForCachingDisplay`, which includes the native SwiftUI autofill overlay (rendered inside `BrowserWebContentView`, same window) and requires no screen-recording permission because the app draws its own views.

Known limitation: in-process window rendering composites what evo draws, not true screen pixels — a compositor-level bug (wrong window level, occlusion) would not be visible. Accepted; the manual UAT pass covers that class.

### v2 (deferred)

`GET /console?tab=` — a Debug-only JS shim forwarding `console.*` through the existing script-message bridge into a per-tab ring buffer. Useful, not needed for the password loop.

## The verification loop

1. `./scripts/xcbuild-debug.sh` and launch the app.
2. Read the token file; `GET /health`.
3. `python3 scripts/fixture-server.py` in the background.
4. `POST /provider {kind: mock}`; navigate to a fixture; `/eval` to focus the username field.
5. `GET /overlay` to assert rows; `/keypress activate`; `/eval` to read filled input values.
6. `POST /screenshot` at each step — evidence attached to Claude's messages and PR descriptions.

## Error handling

- Server startup failure (port in use): log via os_log and continue — the harness must never break normal app launch.
- Dead weak references in the registry: pruned on access; a request against a closed window returns 404.
- `/eval` JS exceptions: returned as `{"error": ..., "jsException": true}` with status 200 (the HTTP call succeeded; the JS failed) so probing for absent DOM state is not an HTTP error.
- Provider switch to `onePassword` while unconfigured: returns the provider's `unavailable` state rather than erroring.

## Security

- `#if DEBUG` compile gate: the server, registry, mock provider availability, and route table do not exist in Release binaries.
- Bind `127.0.0.1` only; per-launch token; token file 0600.
- Reveal-type and provider routes never return real secrets (v1 exposes no reveal route at all). Note the honest limit: `/eval` runs arbitrary JS in the live page, so it can observe DOM state including fields a real provider filled — mitigated by the localhost bind, per-launch token, no-CORS behavior, and the `#if DEBUG` gate, and carrying ~zero marginal risk over the user's own debug build.

## Testing

- Swift Testing units (existing `evoTests` target, `@testable import Evo`): route parsing, token auth rejection, registry pruning, and `MockPasswordProvider` behavior.
- The server's end-to-end behavior is validated by using it against the fixtures — the harness is its own integration test.

## Implementation slices

1. `MockPasswordProvider` + provider switching + unit tests (no server yet; immediately useful in unit tests).
2. Server core: health, windows/tabs, navigate, eval, screenshot.
3. Overlay + keypress + provider routes.
4. Fixtures + fixture server.
5. (v2) console capture.

## Follow-up work this unblocks (separate specs)

- Fix username-only/two-step page autofill (relax the password-field requirement in `password-manager.js`), verified against `login-two-step.html`.
- The "Unlock 1Password…" overlay row (carried gap, upstream SDK hang bug 1Password/onepassword-sdk-go#266).
- Verify 1Password integration against a signed Release-configuration build in `/Applications` (unsigned debug builds fail 1Password's signature check by design).
- Eventually: promote route handlers behind evo's real MCP server for the agent-consolidation vision.
