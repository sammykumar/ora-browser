# 1Password Sidecar Spike — Findings

**Date:** 2026-07-04 · **Machine:** personal MBP (Apple Silicon, macOS 27) · **1Password:** desktop app running, "Integrate with 1Password SDKs" enabled.

Spike code: `tools/op-helper/spike/main.go` (throwaway; deleted after this doc), built with Go 1.26.4, CGO, SDK `github.com/1password/onepassword-sdk-go v0.4.0`.

## Task 0.1 — DesktopAuth works — ✅ GO

After enabling **1Password → Settings → Developer → Integrate with 1Password SDKs**, the spike authorized "Evo Spike" via a Touch ID prompt and listed the personal account's vaults (AT&T, TUA, Perch, Automation, Shared, Personal). Before enabling the setting, `NewClient` returned `channelClosed` ("desktop app connection channel is closed…") — confirming that error also means "integration disabled," indistinguishable from "app not running."

## Task 0.4 — One process per account, no cross-talk — ✅ GO

- Personal (`my.1password.com`) and work (`theuptownagency.1password.com`) each, run as their own process, returned their OWN distinct vault sets (work: TUA Shared Vault, Operations, Engineering, Private — entirely different from personal). No account-name leakage.
- **Design note:** running two account processes *concurrently* on first authorization caused one to fail with `Denied authorization for SDK client` — the 1Password app serializes authorization prompts. `OnePasswordService` must **stagger first-time account authorizations** (authorize one account, wait for approval, then the next) rather than prompting all accounts at once; already-authorized accounts can run concurrently.

## Task 0.3 — Sandbox reachability — ❌ NO-GO (App Sandbox blocks 1Password IPC)

Controlled isolation (same binary, same Developer signature, same bundle id `…spikesandbox`; only the entitlement set varies):

| Configuration | Result |
|---|---|
| Bare binary, no sandbox | ✅ vaults listed |
| Developer-signed `.app` bundle, **no sandbox** | ✅ vaults listed |
| Same bundle, **`com.apple.security.app-sandbox`** | ❌ `channelClosed` |
| Sandbox **+ `application-groups`** (`2BUA8C4S2C.com.1password`, `…com.agilebits`) | ❌ `channelClosed` |
| Sandbox **+ `temporary-exception.mach-lookup.global-name`** (`2BUA8C4S2C.com.1password.browser-helper`) | ❌ `channelClosed` |

**Conclusion:** the App Sandbox is the sole cause (flipping only that entitlement flips the result). It cannot be worked around from a third-party app:

- 1Password gates SDK/browser IPC through the **app group `2BUA8C4S2C.com.1password`** (AgileBits' team `2BUA8C4S2C`). Only code signed by AgileBits can legitimately join that group; Apple will not provision another team's app-group id onto Evo's profile, so the `application-groups` entitlement is embedded but not honored at runtime.
- No `deny(mach-lookup)` was logged, consistent with the lookup living inside that un-provisionable group namespace rather than a global-name service we could except.
- 1Password's own SDK docs scope DesktopAuth to "integrations that run locally on a user's machine" — not sandboxed third-party apps.

Earlier `SIGTRAP` (EXIT 133) crashes were a **red herring**: applying `app-sandbox` to a *bare, non-bundled* executable traps in `_libsecinit_appsandbox` at startup (no bundle id / container). A proper `.app` bundle initializes the sandbox cleanly and then fails at the IPC layer — that bundled test is the valid one.

### Decision required (escalated to Sam)

To use 1Password DesktopAuth, **Evo must not run under the App Sandbox** for the build that talks to 1Password. Options:

- **A — Drop `com.apple.security.app-sandbox` from Evo (`project.yml`).** 1Password works in every build (signed or unsigned). Cost: Evo is no longer sandboxed. Acceptable for a personal, non-App-Store tool (CLAUDE.md: no App Store intent; Sparkle/release pipeline disabled). **Recommended.**
- **B — Keep the sandbox, rely on the unsigned dev build.** `scripts/xcbuild-debug.sh` builds unsigned (`CODE_SIGNING_REQUIRED=NO`); the sandbox entitlement isn't enforced without a valid signature carrying it, so 1Password works in the day-to-day dev build. Cost: any signed/notarized build breaks 1Password; fragile. (Needs one confirmation: that the unsigned debug build genuinely doesn't enforce the entitlement — verify at Task 1.14.)

Slices 1+ assume the outcome of this decision. The `PasswordProvider` seam, sidecar, and Swift code are unaffected either way; only `project.yml` entitlements change.

## Task 0.5 — Auth cadence & lock-hang — follow-ups (not architecture-critical)

- **Cadence:** within an active session, once "Evo Spike" is authorized for an account, subsequent runs list vaults without a fresh Touch ID prompt. Per 1Password docs the authorization is time-bound to ~10 min of inactivity and revoked on account lock; the SDK auto-re-inits on `DesktopSessionExpired`, re-triggering the prompt. Full 10-min idle re-prompt timing not yet stopwatch-measured — confirm during Slice 1 real use.
- **Lock-hang (#266):** not yet reproduced in this spike. The sidecar's per-request watchdog (goroutine + timer + `os.Exit(1)`, Task 1.3) plus Evo's respawn is retained as the recovery regardless; re-verify once the real sidecar exists.

## Kept from the spike

`tools/op-helper/go.mod` + `go.sum` (SDK v0.4.0 resolved), `scripts/build-op-helper.sh` (to be finalized in Task 1.4). Everything under `tools/op-helper/spike/` is deleted.
