# Passkey entitlement runbook

The passkey feature is gated on Apple granting the **managed capability**
`com.apple.developer.web-browser.public-key-credential` to App ID
`com.skproductions.evobrowser`. Plan: `docs/superpowers/plans/2026-07-05-passkey-support.md`.
Spec: `docs/superpowers/specs/2026-07-05-passkey-support-design.md`.

## 1. File the request (Account Holder only)

1. Sign in at developer.apple.com → Certificates, Identifiers & Profiles.
2. Identifiers → select the `com.skproductions.evobrowser` App ID.
3. Open the **Capability Requests** tab.
4. Find the web-browser passkey capability (WebAuthn / public-key-credential). Click **Request**.
5. In the form, describe the use: "Evo is a WKWebView-based macOS web browser; it needs to
   perform WebAuthn passkey registration/assertion for arbitrary relying parties so users can
   sign in with passkeys stored in system providers (1Password, iCloud Keychain), exactly as
   Safari/Chrome/Firefox do."
6. Submit. **Record the submission date here:** ____________________

### If the capability is not listed or the form errors
Known friction: the capability may not appear on the App ID, or the form may return
"your account can't access this page." Fallback: contact Apple Developer Support / Developer
Relations directly, reference the entitlement by exact name
(`com.apple.developer.web-browser.public-key-credential`), and cite that it is the documented
path for third-party browsers to use system passkey providers.

## 2. When Apple grants it
Resume the plan at **Task 4**. In short:
- Regenerate the App ID's provisioning profile so it includes the entitlement.
- Switch the Debug build to signed (Task 4); carry it into Release (Task 5).
- Run passkey validation UAT (Task 6).

## 3. If Apple denies it
There is no workaround for arbitrary-site passkeys in WKWebView. Escalate to Sam: ship
without passkeys, or hold the feature. Do not attempt to reimplement 1Password's injected
`navigator.credentials` shim — it brokers to the desktop app and is not reproducible without
1Password's signing/app-group trust.
