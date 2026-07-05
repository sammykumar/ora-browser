# Passkey (WebAuthn) support in Evo — design

**Date:** 2026-07-05
**Status:** Design approved; implementation gated on an external Apple approval (see §3).
**Relates to:** the 1Password integration (`2026-07-04-1password-integration-design.md`). Passkeys were scoped *out* of that work; this spec brings them in as a ship blocker.

## 1. Goal

Passkey sign-in **and** registration work on any website in Evo, brokered by macOS to whichever passkey provider is active — 1Password when it is the active provider, otherwise iCloud Keychain (Apple Passwords). This matches Safari's behavior and Chrome/Firefox on macOS.

Success = on a real site (`webauthn.io`, GitHub passkey login), calling `navigator.credentials.get()` / `.create()` pops the system passkey sheet and completes the ceremony via the active provider, with **zero** WebAuthn-specific application code.

## 2. How it works — and what we deliberately do NOT build

When a page calls the WebAuthn JS API, **WKWebView performs the ceremony natively** and presents the system passkey sheet — *but only if the hosting app carries the entitlement `com.apple.developer.web-browser.public-key-credential`*. This is Apple's supported path for third-party browsers; it is exactly how Chrome and Firefox surface Apple Passwords / third-party passkeys today.

With the entitlement present, the behavior is **automatic**. We do NOT write:

- Any `ASAuthorizationController` / `ASAuthorizationPlatformPublicKeyCredentialProvider` code.
- Any credential-provider extension.
- Any `ASWebAuthenticationSession` bridge.
- Any WebAuthn JavaScript, and no change to `password-manager.js` or the JS↔Swift bridge.
- Any change to the Go `op-helper` sidecar or the `PasswordProvider` fill path.

Without the entitlement, WKWebView's WebAuthn calls reject silently — which is the "passkey pages don't work" symptom observed during 1Password UAT. **The entire feature is therefore: carry the entitlement on a properly-signed build.** There is no meaningful WebAuthn engineering.

The sidecar / form-fill integration and passkeys are orthogonal: form-fill covers username+password (and TOTP); passkeys are an OS-brokered credential type. 1Password participates in *both*, by different mechanisms.

## 3. The external gate (the long pole)

`com.apple.developer.web-browser.public-key-credential` is a **managed (restricted) capability**: Apple must assign it to the team before a build can be signed with it.

**Request path** (Account Holder, on the paid developer account):
Certificates, Identifiers & Profiles → **Identifiers** → the Evo App ID → **Capability Requests** tab → find the web-browser passkey capability → **Request** → submit the form.

**Known friction (documented so we don't rediscover it):**
- The capability may not appear on the macOS App ID, and/or the request form may error ("your account can't access this page"). Fallback: contact Apple Developer support / Developer Relations directly and reference the entitlement by name.
- Organization accounts require the **Account Holder** to submit.

**Hard consequences of the gate:**
- **Nothing is testable until Apple grants it** — a signed build cannot carry an unassigned managed entitlement, so we cannot verify passkeys before approval.
- **If Apple denies it, there is no workaround** for arbitrary-relying-party passkeys in WKWebView. That would force an explicit ship decision (ship without passkeys, or hold the feature). This is the single hard risk of the whole design.

Realistic outcome: indie/small developers have been approved, so this is expected to succeed, but the timeline (days–weeks) is outside our control.

## 4. Concrete changes (all small; gated on the grant)

1. **`project.yml` entitlements** — re-add exactly one key: `com.apple.developer.web-browser.public-key-credential: true`. Do **not** re-add the default-browser parent `com.apple.developer.web-browser` (that is a separate, unneeded feature).
2. **Signing (decision: switch the whole debug build to signed).** Today's debug build is unsigned (`CODE_SIGN_IDENTITY=""`), which cannot carry the entitlement. Change debug to sign with an Apple Development certificate and a provisioning profile that includes the entitlement. Expected specifics:
   - Likely `CODE_SIGN_STYLE: Manual` with a named provisioning profile, because restricted entitlements frequently do not provision cleanly under automatic signing.
   - **Keep `ENABLE_HARDENED_RUNTIME: NO` on debug** so the embedded Go sidecar binary and its `dlopen` of the 1Password IPC dylib keep working (entitlement enforcement does not require hardened runtime).
   - `scripts/xcbuild-debug.sh` updated accordingly (it currently forces `CODE_SIGN_IDENTITY=""` / `CODE_SIGNING_REQUIRED=NO`).
3. **Release build** — add the same entitlement to the Developer ID Release configuration's profile.
4. **No Swift / JS / Go source changes.**

## 5. Validation (this is the "spike")

On a signed, entitled build:

- **Authentication (`get`):** sign in with an existing passkey at GitHub (and/or `webauthn.io`) → system sheet appears → 1Password (set as active provider) fills the passkey → login completes.
- **Registration (`create`):** create a passkey at `webauthn.io` → stored in the active provider.
- **Provider coverage:** confirm behavior with 1Password as active provider, and (sanity) with iCloud Keychain.
- **Regression:** confirm the 1Password sidecar still spawns on first login-field focus and fills username/password + TOTP (i.e., moving debug to a signed build did not break the embedded binary or its IPC).

## 6. Out of scope (YAGNI)

- Any in-app "passkeys require setup" UI for the un-entitled state — that state exists only during development before the grant; once shipped it is always entitled.
- The default-browser entitlement `com.apple.developer.web-browser`.
- iOS/iPadOS (tracked separately as the general port; same entitlement applies there when that port is pursued).

## 7. Sequencing

1. **File the Apple request now** (Account Holder, §3). This is the critical-path, external step.
2. **In parallel:** stage the `project.yml` entitlement + signing changes and this request guide on a branch, flip-ready. Cannot be verified until the grant.
3. **On approval:** enable the entitlement, generate/download the provisioning profile, build signed, run §5 validation.
4. **If denied:** escalate the ship decision to the user (ship-without vs. hold).

## 8. References

- [Apple: `com.apple.developer.web-browser.public-key-credential`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential)
- [Apple: Passkey use in web browsers](https://developer.apple.com/documentation/authenticationservices/passkey-use-in-web-browsers)
- [Apple: Capability Requests (how to request managed capabilities)](https://developer.apple.com/help/account/capabilities/capability-requests/)
- [Apple Developer Forums: WKWebView browser WebAuthn/Yubikey — entitlement approved, works with no extra code](https://developer.apple.com/forums/thread/774904)
- [passkeys.dev: macOS reference](https://passkeys.dev/docs/reference/macos/)
