# Passkey entitlement runbook

The passkey feature is gated on Apple granting the **managed capability**
`com.apple.developer.web-browser.public-key-credential` to App ID
`com.skproductions.evobrowser`. Plan: `docs/superpowers/plans/2026-07-05-passkey-support.md`.
Spec: `docs/superpowers/specs/2026-07-05-passkey-support-design.md`.

## 1. File the request (Account Holder only)

1. Sign in at developer.apple.com → Certificates, Identifiers & Profiles.
2. Identifiers → select the `com.skproductions.evobrowser` App ID.
3. Open the **Capability Requests** tab.
4. Find the row named **"Web Browser Public Key Credential Requests"** (this IS
   `com.apple.developer.web-browser.public-key-credential`). Click its **+ / Request** —
   that opens the request form. **Request ONLY this row.** Do NOT request the other
   "Web Browser …" entries (Engine Host/Networking/Rendering/Web Content, JIT Access,
   Embedded Browser Engine, Default Web Browser, Browser App Installation) — none are needed.
5. Fill the form:
   - **App Name:** `Evo Browser`
   - **App Store URL / App Apple ID:** blank (not on the App Store)
   - **Bundle ID of App:** `com.skproductions.evobrowser`
   - **Is your app a web browser on macOS?** → **Yes**
   - **Does your web browser support WebAuthn for web content?** → **Yes** (WKWebView does)
   - **Integrate WebAuthn with passkeys in iCloud Keychain?** → **Yes** (WKWebView's native
     WebAuthn surfaces iCloud Keychain AND 1Password automatically once entitled; accurate + favorable)
   - **Link/download/eval credentials textarea:** "Evo is a personal, WebKit/WKWebView-based
     macOS web browser (GPL-3.0), not distributed on the App Store or publicly released.
     Source (public): https://github.com/sammykumar/evo-browser. I can provide a signed, notarized
     build for evaluation on request — please advise the preferred delivery method."
     (Repo is public as of 2026-07-05; Apple may still ask for a runnable notarized build.)
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
