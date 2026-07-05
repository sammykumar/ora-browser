# 1Password Integration — Design

**Date:** 2026-07-04
**Status:** Approved direction; slice 1 not started

## Goal

Make 1Password a first-class password provider in Evo, with the functional feel of the
1Password Chrome/Safari extension: inline autofill suggestions under login fields, save/update
prompts on form submit, and one-time password (TOTP) support — all surfaced through Evo's
existing autofill overlay and Passwords settings pane.

## Constraints (settled during brainstorming)

- **Self-contained.** Evo runs on two machines (personal MBP and work MBP). No dependency on
  Homebrew or the `op` CLI. Everything Evo needs ships inside `Evo.app`; the only external
  requirement is the 1Password desktop app with Settings → Developer → "Integrate with other
  apps" enabled.
- **Minimal auth prompts.** A live spike of the `op` CLI was rejected: per-process authorization
  caching caused repeated prompts, and warm multi-account listing took ~7s. The design must
  authorize once per Evo launch (re-prompting only when 1Password itself locks).
- **Account-agnostic.** Sam has two 1Password accounts today (personal + Uptown Agency); the
  design supports N accounts dynamically, with per-account badges in the overlay.
- **No Swift SDK exists.** Official 1Password SDKs are Go / JavaScript / Python. Go is the only
  one that compiles to a single bundleable binary, so the integration vehicle is a Go sidecar.
- **Evo never sees 1Password credentials.** All trust ceremonies (authorization, Touch ID) are
  brokered by the 1Password desktop app via the SDK's `DesktopAuth`.

### Spike data (2026-07-04, personal MBP)

| Measurement | Result |
|---|---|
| `op item list` warm, both accounts | ~7s |
| `op item list` warm, personal account only | ~0.5s (558 items) |
| `op item list` warm, work account only | ~6.3s (311 items) |
| `op item get` single item with reveal | ~6.6s (cold-ish session) |

Conclusion: item metadata must be cached in memory up front; per-focus queries are not viable.

## Architecture

Three pieces, one seam:

### 1. Go sidecar — `evo-op-helper`

- New `tools/op-helper/` directory: a small Go module using the official
  [1Password Go SDK](https://github.com/1Password/onepassword-sdk-go) with
  `WithDesktopAppIntegration` (DesktopAuth).
- Compiled as a universal (arm64 + x86_64) binary, embedded in `Evo.app` via an XcodeGen
  copy-files phase.
- **The compiled binary is committed to the repo** so the work MBP can build Evo without a Go
  toolchain. A script (`scripts/build-op-helper.sh`) regenerates it when the helper source
  changes. Accepted trade-off: ~15MB repo bloat, pragmatic for a personal tool.
- Spawned **once, lazily** — the first time the 1Password provider needs it — and kept alive for
  Evo's lifetime, holding the authorized SDK session(s). This is what collapses auth to one
  Touch ID prompt per Evo launch.
- Protocol: newline-delimited JSON request/response over stdin/stdout (same pattern as the
  Claude panel's external-binary integration). Requests:
  - `status` — desktop-app availability, per-account session state
  - `authorize` — create SDK client(s); triggers the 1Password app's approval/Touch ID UI
  - `listItems` — metadata only: item id, title, username, website URLs, vault, account,
    has-TOTP flag. Never passwords.
  - `reveal(accountID, itemID)` — username + password for one item
  - `totp(accountID, itemID)` — current one-time code
  - `saveItem(accountID, vaultID, url, username, password, existingItemID?)` — create or update
    a Login item with the website URL attached
  - `generatePassword` — SDK password generation (optional; Evo has its own generator)
- SDK version pinned in `go.mod`; SDKs are v0.x so minor bumps are deliberate, not automatic.

### 2. Swift service — `OnePasswordService`

New singleton in `evo/Features/Passwords/Services/`:

- Owns the sidecar lifecycle: resolve binary inside the app bundle, spawn, restart once on
  crash, terminate on app quit.
- Async request/response over the stdin/stdout pipes; requests are serialized with ids so
  responses match up.
- **In-memory metadata cache**: filled once after authorization, refreshed in the background
  (periodic + on save). The overlay always reads from this cache — the slow work-account
  listing never blocks UI. The cache holds no secrets and is never persisted.
- Publishes state for the UI: `unavailable` (helper or desktop app missing / integration
  disabled), `locked`, `syncing`, `ready`.
- Accounts are a dynamic list. Preferred: auto-discover signed-in accounts if the sidecar spike
  finds a way (the SDK does not document account enumeration). Fallback (assume this until
  proven otherwise): a per-machine account list in Evo settings — the user types each account
  name once; the sidecar creates one SDK client per entry.

### 3. `PasswordProvider` protocol (the refactor)

`PasswordAutofillCoordinator` is currently hard-wired to `PasswordManagerService` and gates
behavior on two descriptor booleans (`usesBuiltInVault` / `usesBuiltInOverlay`) that cannot
express "external vault that fills AND saves." Replace those gates with a protocol, roughly:

```swift
protocol PasswordProvider {
    func credentials(for url: URL, containerID: UUID?) async -> [ProviderCredential]
    func reveal(_ credential: ProviderCredential) async throws -> RevealedCredential
    func save(url: URL, username: String, password: String, target: SaveTarget) async throws
    func totp(for credential: ProviderCredential) async throws -> String?
    var stateForUI: ProviderState { get }
}
```

Two implementations:

- `EvoPasswordProvider` — wraps the existing `PasswordManagerService` (Keychain vault).
  **Behavior must be preserved bit-for-bit**, including its authenticate-on-every-fill policy,
  email suggestions, and generated-password flow.
- `OnePasswordProvider` — wraps `OnePasswordService`.

`PasswordManagerProviderRegistry` enables the existing commented-out `.onePassword` descriptor
and maps the selected kind to the active provider instance. `SettingsStore.passwordManagerProvider`
already persists the selection.

### Fill data flow

page focus event → bridge JS (existing) → `PasswordAutofillCoordinator` → active provider →
metadata cache lookup (instant) → overlay shows badged suggestions → user picks →
`reveal` via sidecar (silent; session already authorized) → existing `fillCredentials` JS
pipeline fills the form.

Everything downstream of the provider boundary — overlay positioning, keyboard navigation,
fill/highlight JS, auto-submit — is reused unchanged.

## Behaviors

### Onboarding (per machine, one time)

1. In the **1Password app**: Settings → Developer → enable "Integrate with other apps." Evo
   detects when this is off and shows the instruction in settings; it cannot (by design) enable
   it itself.
2. In **Evo settings**: select "1Password" in the provider dropdown, add account name(s) (no
   password, no secret key — just the account identifier), click Connect. The 1Password app
   presents its own authorization dialog; the user approves with Touch ID. Evo never renders a
   credential entry UI for 1Password.
3. Thereafter: each Evo launch reuses the trust silently; at most a Touch ID prompt from
   1Password on first credential use if the vault is locked.

### Settings — Passwords pane (1Password selected)

- "Saved Credentials" (Evo Keychain list) is replaced by a **1Password connection panel**:
  status line (`Connected · 2 accounts · 869 items` / `Locked` / `1Password app not set up` /
  `Syncing…`), account list with add/remove, Reconnect button.
- Toggles shown: Autofill on login forms, Auto-submit after autofill, Prompt to save to
  1Password. (Evo-vault-specific toggles hide.)
- Switching the dropdown back to Evo Passwords restores today's UI exactly; the Keychain vault
  is never touched by the 1Password provider.

### Autofill overlay

- Suggestion rows show item title + username + a small **account badge** (scales to N accounts).
- Vault locked → a single **"Unlock 1Password…"** row; Touch ID fires only when clicked, never
  on field focus.
- Metadata sync in progress → transient "Syncing 1Password…" row.
- Private windows: **no autofill**, matching current coordinator behavior (revisit later if
  wanted).

### Save & update

- On form submit (existing bridge event), if the username+password doesn't match a known
  1Password item for that site: show Evo's save prompt with an **account picker** (when >1
  account). Sidecar creates the Login item with the website URL attached (or updates the
  existing item on password change) so it round-trips to all other 1Password clients.
- The existing "Never on This Site" suppression list applies regardless of provider.

### TOTP

- Bridge JS learns to recognize one-time-code fields (`autocomplete="one-time-code"` and
  common heuristics). If such a field appears after filling a TOTP-bearing item, the overlay
  offers **"Fill one-time code."**
- Fallback (extension parity): after any fill from a TOTP-bearing item, the current code is
  copied to the clipboard with a toast, using the existing 90-second sensitive-clipboard clear.
- Codes are fetched from the sidecar on demand and never cached.

## Out of scope (explicit decisions, not omissions)

- **Passkeys** — different macOS plumbing entirely (native WKWebView WebAuthn via an
  Apple-restricted entitlement, not the sidecar). **No longer deferred** — now an active ship
  blocker, scoped in its own spec: `2026-07-05-passkey-support-design.md`. See the gap analysis
  below.
- **Identities / credit-card autofill** — logins only.
- **Item management UI in Evo** — viewing/editing items happens in the 1Password app; Evo is a
  consumer (fill + save only).
- **Bitwarden** — the registry placeholder stays commented out; the `PasswordProvider` protocol
  is the seam it would use later.

## Gap analysis vs. the 1Password Chrome extension (2026-07-05)

Derived from reading the 1Password Chrome extension source (v8.12.26.40, at
`~/Library/Application Support/Arc/User Data/Default/Extensions/aeblfdkhhhdcdjpifhhbdiojplfjncoa`).
The extension is a full password-manager client: a ~2.7MB service worker brokering to the
1Password **desktop app over `nativeMessaging`** (the same broker model as our Go sidecar —
biometric unlock lives in the desktop app), a ~190KB field-detection **heuristics engine**,
inline field-attached UI (menu / save-notification / modal / universal-sign-on), and
all-frames page-injected content scripts.

**Purpose of this table:** capture the full surface so Sam can set build priority for parity.
The **Priority** column is intentionally blank — to be filled in by the user.

### Parity — Evo already matches
| Capability | Evidence in extension | Evo today |
|---|---|---|
| Login fill (username/password), biometric-brokered | nativeMessaging ↔ desktop app | ✅ sidecar, same broker model |
| TOTP fill | `totp` / `one-time` codes | ✅ Slice 4 |
| Save / update login prompts | `SaveLogin` / prompt-save | ✅ Slice 3 (create + update, dedupe by username) |
| Multi-account | `accounts` throughout | ✅ one process per account |
| Password generation | `generatePassword` | ✅ generated-password suggestion |
| URL / subdomain matching | — | ✅ `hostsMatch` |

### Gaps — in the extension, missing/weaker in Evo
| # | Capability | Extension evidence | Evo today | Category | Scope note | Priority |
|---|---|---|---|---|---|---|
| 1 | **Passkeys / WebAuthn** | `passkey`×504, `webauthn`×379; injects its *own* `navigator.credentials` shim (`webauthn.js` + MAIN-world listeners) brokering to the desktop app | ❌ none | **Ship blocker** | Evo's path is *simpler* — native WKWebView WebAuthn via the `com.apple.developer.web-browser.public-key-credential` entitlement; the OS routes to 1Password-as-provider. We do **not** replicate their shim. See `2026-07-05-passkey-support-design.md`. | _(user)_ |
| 2 | **Credit-card fill** | `creditCard`×123 | ❌ logins only | Autofill breadth | Needs sidecar item-type support + bridge detection for card fields. | _(user)_ |
| 3 | **Identity / address fill** | `identity`×249, `address`×315 | ❌ | Autofill breadth | Same shape as #2 (new item types + field heuristics). | _(user)_ |
| 4 | **SSH key** | `sshKey`×47 | ❌ | Dev workflow | 1Password's SSH agent is separate from the browser; low browser relevance. | _(user)_ |
| 5 | **HTTP Basic-auth fill** | `webRequestAuthProvider` / `onAuthRequired` | ❌ | Autofill breadth | WKWebView exposes this via `didReceive challenge`; no Chrome-extension equivalent needed. | _(user)_ |
| 6 | **Watchtower** (breach / compromised-password checks) | `watchtower`×371, `api.pwnedpasswords.com` in CSP | ❌ | Security hygiene | Standalone feature; independent of fill path. | _(user)_ |
| 7 | **Masked email** (Fastmail aliases) | `maskedEmail` / `fastmail`×70 | ❌ | Convenience | Requires Fastmail account + provider API. | _(user)_ |
| 8 | **Universal Sign-On / SSO** | `universalSignOn`×68 | ❌ | Enterprise | Sign into 1Password itself via IdP; not autofill. | _(user)_ |
| 9 | **Secure remote autofill** (cross-device pairing) | director.ai pairing scripts | ❌ | Edge | Cross-device; out of scope for a single-user desktop tool. | _(user)_ |
| 10 | **Kolide device-trust**, context-menu fill, downloads/notifications surfaces | manifest permissions + `kolide.js` | ❌ | Enterprise / polish | Kolide is enterprise-only; context-menu fill is minor polish. | _(user)_ |

### Partial — Evo has a weaker version
| Capability | Extension | Evo today |
|---|---|---|
| Field detection | ~190KB heuristics engine, all frames, multi-step forms | Lean `password-manager.js` on password/OTP/email-or-username inputs — adequate for our scope, less robust on exotic/iframe/multi-step forms |
| Inline UI | Menu attached to the focused field + save/modal notifications | Single overlay — functionally close for fill, less rich |
| Auto-submit after fill | `autoSubmit` present | Not implemented |

### Recommended read (author's take, non-binding)
Ship-relevant gaps are **#1 passkeys** (already the active blocker, via a genuinely simpler
native path than the extension's shim) and, if broader autofill parity is wanted later,
**#2 credit-card / #3 identity** fill. Items #4–#10 are enterprise/edge/hygiene features that
a personal, single-user tool can reasonably skip. Field-detection robustness (Partial) is the
most likely source of real-world friction and is worth incremental hardening independent of
new item types.

## Error handling

- Desktop app missing, integration disabled, account not authorized, sidecar crash — all
  degrade to a visible status in the settings panel and a quiet no-op in the overlay. Never a
  blocking dialog mid-browse.
- Sidecar gets **one automatic restart** per failure; a second failure → `unavailable` until
  Reconnect is clicked.
- Secrets exist only in transit (sidecar stdout → Swift → JS fill call). No secret is written
  to disk, logged, or held in the metadata cache. Sidecar request/response logging, if any,
  must redact payloads.

## Delivery slices (each independently shippable)

1. **Fill** — sidecar skeleton (`status`/`authorize`/`listItems`/`reveal`), `PasswordProvider`
   protocol refactor with `EvoPasswordProvider` preserving current behavior bit-for-bit,
   1Password suggestions filling via the overlay. Single account. Includes the sidecar spike
   task: verify DesktopAuth end-to-end and whether account auto-discovery is possible.
2. **Multi-account + settings panel** — account list UI, overlay badges, status states,
   prebuilt-binary build wiring (`scripts/build-op-helper.sh`, XcodeGen embed).
3. **Save/update** — submit-driven prompts, account picker, sidecar `saveItem`.
4. **TOTP** — OTP field detection in bridge JS, fill row + clipboard fallback.

## Testing

- `PasswordProvider` gets a fake in-memory implementation so overlay/matching/save logic is
  testable in `evoTests` (Swift Testing) without 1Password installed.
- Dedicated cases for URL-matching rules (subdomain handling, `www.` stripping, ports,
  http-vs-https) — the historical home of autofill bugs.
- Regression cases proving `EvoPasswordProvider` matches current `PasswordManagerService`
  behavior through the new protocol.
- Sidecar: small Go test for request routing; end-to-end verified manually against real login
  pages (including a TOTP-bearing login) on both machines.

## Open questions (to resolve in slice 1)

- Can the sidecar enumerate signed-in accounts, or does the settings fallback stand?
- SDK `DesktopAuth` session lifetime in practice: confirm one authorization per sidecar
  process, and what happens across 1Password auto-lock (expected: next request blocks on a
  Touch ID prompt brokered by the app).
- Whether `listItems` across many vaults is fast enough for a simple full refresh, or needs
  per-vault incremental sync.
