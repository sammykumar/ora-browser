# FORK_PATCHES.md

Tracks edits this fork makes to upstream-owned files, so they can be re-applied after rebasing on `the-ora/browser`. Pure additions in new files do not need to be tracked here.

## `project.yml`

Upstream defines code signing for **the Ora team** and Sparkle auto-update pointing at **the Ora appcast**. Re-pointing those at us / disabling them is the core fork patch.

**Re-apply after every rebase:**

| Section | Upstream value | Fork value | Why |
|---|---|---|---|
| `options.bundleIdPrefix` | `com.orabrowser` | `com.skproductions.evo` | Avoid collision with Ora installs; identify our build |
| `targets.ora.info.properties.SUFeedURL` | `https://the-ora.github.io/browser/appcast.xml` | *(removed)* | Disable Sparkle auto-update — we don't have an appcast yet |
| `targets.ora.info.properties.SUPublicEDKey` | Ora's pubkey | *(removed)* | Their key, not ours |
| `targets.ora.info.properties.SUEnableAutomaticChecks` | `YES` | `NO` | Disable Sparkle |
| `targets.ora.info.properties.SUEnableInstallerLauncherService` | `YES` | `NO` | Disable Sparkle helper |
| `targets.ora.info.properties.CFBundleURLTypes[0].CFBundleURLName` | `Ora Browser` | `Evo Browser` | URL handler display name |
| `targets.ora.settings.base.PRODUCT_NAME` | `Ora` | `Evo` | App bundle becomes `Evo.app` |
| `targets.ora.settings.base.PRODUCT_MODULE_NAME` | (unset, defaults to `Ora` via `PRODUCT_NAME`) | `Ora` (explicit) | Pin the Swift module name so upstream's `@testable import Ora` in `oraTests/` keeps compiling without us editing those files. |
| `targets.ora.settings.base.PRODUCT_BUNDLE_IDENTIFIER` | `com.orabrowser.app` | `com.skproductions.evobrowser` | Confirmed by Sam |
| `targets.ora.settings.base.SUFeedURL` | (Ora appcast URL) | *(removed)* | Same as Info plist |
| `targets.ora.settings.base.SUPublicEDKey` | Ora's pubkey | *(removed)* | Same as Info plist |
| `targets.ora.settings.base.SUEnableAutomaticChecks` | `YES` | `NO` | Same as Info plist |
| `targets.ora.settings.base.SUEnableInstallerLauncherService` | `YES` | `NO` | Same as Info plist |
| `targets.ora.settings.configs.Debug.CODE_SIGN_STYLE` | `Manual` | `Automatic` | We don't have Ora's provisioning profile; let Xcode pick our personal team |
| `targets.ora.settings.configs.Debug.CODE_SIGN_IDENTITY` | `Developer ID Application` | *(removed)* | Don't force Developer ID for local Debug builds |
| `targets.ora.settings.configs.Debug.DEVELOPMENT_TEAM` | `3Y566D2A4G` | *(removed)* | Ora's team, not ours |
| `targets.ora.settings.configs.Debug.PROVISIONING_PROFILE_SPECIFIER` | `ora-profile-working` | *(removed)* | Ora's profile, not ours |
| `targets.ora.settings.configs.Release.DEVELOPMENT_TEAM` | `3Y566D2A4G` | *(removed)* | TBD — fill in our team if/when we do signed releases |
| `targets.ora.settings.configs.Release.PROVISIONING_PROFILE_SPECIFIER` | `ora-profile-working` | *(removed)* | TBD |
| `targets.oraTests.settings.base.TEST_HOST` | `$(BUILT_PRODUCTS_DIR)/Ora.app/Contents/MacOS/Ora` | `$(BUILT_PRODUCTS_DIR)/Evo.app/Contents/MacOS/Evo` | Match new `PRODUCT_NAME` |
| `targets.ora.entitlements.properties.com.apple.developer.web-browser` | `true` | *(removed)* | Apple-restricted entitlement (default-browser registration). Blocks automatic signing until Apple approves a Request Access form. Re-add after approval. |
| `targets.ora.entitlements.properties.com.apple.developer.web-browser.public-key-credential` | `true` | *(removed)* | Apple-restricted entitlement (native passkey/WebAuthn provider). Same blocker as above. Re-add after approval. |

Things deliberately **not** patched (kept as upstream):

- `name: Ora` and `targets.ora`/`oraTests`/`schemes.ora` — internal target/scheme/project names, never user-facing. Renaming would create huge rebase friction.
- `sources: path: ora` — source directory stays `ora/`. Same reason.
- `ASSETCATALOG_COMPILER_APPICON_NAME: OraIcon` / `OraIconDev` — internal asset names. Replacing the icon **image content** is a Phase 2/3 task (design work).
- `entitlements.path: ora/Info/ora.entitlements` — file path, internal.

## User-facing string rebrand (Swift)

Strings that the user sees in the UI or in dialogs were rebranded from "Ora" to "Evo". Re-apply if upstream introduces new copy. Internal Swift identifiers (`OraApp`, `OraRoot`, `OraCommands`, `OraButton`, `OraIcon`, `OraBrowserScripts`, `OraToggleStyle`, `OraTextField`, `oraShortcut`, `oraDefault`, etc.) stay as `Ora*` — they're never user-visible and renaming them creates massive rebase friction.

| File | Change |
|---|---|
| `ora/App/OraRoot.swift` | "Quit Ora?" → "Quit Evo?"; `deleteSwiftDataStore("OraData.sqlite")` → `"EvoData.sqlite"` |
| `ora/App/OraCommands.swift` | "About Ora" → "About Evo"; About dialog `"Ora Browser"` → `"Evo Browser"` and copyright `"© 2025 Ora Browser"` → `"© 2025 SK Productions LLC"` |
| `ora/Features/Settings/Sections/GeneralSettingsView.swift` | "Ora Browser" → "Evo Browser"; "Make Ora your default browser" → "Make Evo your default browser" |
| `ora/Features/Passwords/Views/PasswordsWindow.swift` | "Unlock your saved passwords in Ora" → "...in Evo" |
| `ora/Features/Settings/Sections/PasswordsSettingsView.swift` | "Unlock your saved passwords in Ora" → "...in Evo" |
| `ora/Features/Passwords/Services/PasswordManagerService.swift` | Two error strings: "Ora couldn't decode..." / "Ora can only save..." → "Evo couldn't..." / "Evo can only..." |
| `ora/Features/Passwords/Services/PasswordManagerProviderRegistry.swift` | "Ora Passwords" / "Store encrypted credentials in Ora and show Ora's autofill overlay." → Evo wording |
| `ora/Features/Browser/URLBar/URLBar.swift` | "Shared from Ora" → "Shared from Evo" |
| `ora/Features/Browser/Components/LinkPreview.swift` | "Ora \(version)" → "Evo \(version)" |
| `ora/Features/Downloads/Views/DownloadHistoryRow.swift` | "Remove from Ora" → "Remove from Evo" |

## Bundle-prefix and storage-path rebrand

The bundle ID changed (`com.orabrowser.app` → `com.skproductions.evobrowser`), so identifiers under the old prefix were stale. All persistent identifiers were rewritten to match. **This orphans any local data created before the rebrand** (SwiftData store, compiled WKContentRuleLists, keychain entries) — accepted as a one-time cost.

| File | Change |
|---|---|
| `ora/Core/Extensions/ModelConfiguration+Shared.swift` | `"OraData"` → `"EvoData"`; `path: "Ora/OraData.sqlite"` → `"Evo/EvoData.sqlite"` |
| `ora/Features/Privacy/Services/ContentBlockerArtifactStore.swift` | `identifierPrefix = "com.orabrowser.adblock"` → `"com.skproductions.evobrowser.adblock"`; `.appendingPathComponent("Ora", ...)` → `"Evo"` |
| `ora/Features/Privacy/Services/BrowserPrivacyService.swift` | `StaticRuleListIdentifier` raw values: `com.orabrowser.privacy.*` → `com.skproductions.evobrowser.privacy.*` (trackers, third-party cookies, all cookies — `.v1` suffix preserved) |
| `ora/Features/Passwords/Services/PasswordManagerService.swift` | Keychain `serviceName`: `"com.orabrowser.app.passwords"` → `"com.skproductions.evobrowser.passwords"` |
| `ora/Core/Services/App/UpdateService.swift` | Logger subsystem `com.orabrowser.ora` → `com.skproductions.evobrowser`; **and** `feedURLString(for:)` returns `nil` instead of the Ora appcast URL (Sparkle stays disabled even if updater wiring is re-enabled) |
| `ora/Features/Importer/Services/Importer.swift` | Logger subsystem rename (same pattern) |
| `ora/Features/Search/Services/SearchEngineService.swift` | Logger subsystem rename |
| `ora/Features/History/Services/HistoryManager.swift` | Logger subsystem rename |
| `ora/Features/FindInPage/FindController.swift` | Logger subsystem rename |
| `ora/Shared/Layout/NSPageView.swift` | Logger subsystem `com.orabrowser.app` → `com.skproductions.evobrowser` |

## Page-DOM JS identifier rebrand

Injected-script globals and `data-*` attributes were renamed `__ora*` → `__evo*` / `data-ora-*` → `data-evo-*`. These show up in the page DOM and DevTools. The Swift sides that call into these globals were updated in lockstep — if upstream adds a new `__ora*` identifier in either an injected JS file or a Swift string literal, both must be re-renamed.

| File | Change |
|---|---|
| `ora/Resources/WebScripts/password-manager.js` | `__oraPasswordManagerInstalled`, `__oraPasswordManager`, `oraPasswordFieldId`, `data-ora-password-field-id`, `ora-password-${random}` → `__evo*` / `evo*` equivalents |
| `ora/Features/Passwords/Services/PasswordAutofillCoordinator.swift` | `window.__oraPasswordManager` → `window.__evoPasswordManager` (must match `password-manager.js`) |
| `ora/Core/BrowserEngine/Scripts/OraBrowserScripts.swift` | All inline JS: `__oraBridge`, `__oraMediaInstalled`, `__oraMedia`, `__oraTriggerPiP`, `__oraWasPlayed`, `__oraAttached` → `__evo*` |
| `ora/Features/Tabs/State/TabManager.swift` | `window.__oraTriggerPiP` → `window.__evoTriggerPiP` (two call sites) |
| `ora/Features/Player/State/MediaController.swift` | All `window.__oraMedia.*` calls → `window.__evoMedia.*` |
| `ora/Features/Privacy/Services/BrowserPrivacyService.swift` | `__oraFingerprintingProtectionInstalled` → `__evo*`; fingerprinting profile `'ora-'`/`'ora-group-'` deviceId prefixes → `'evo-'`/`'evo-group-'`; user script name `"ora-fingerprinting-protection"` → `"evo-fingerprinting-protection"` |

## Repo-level docs and metadata

This is a personal, single-user fork, so the upstream community/process docs and Github metadata that assume external contributors were rewritten or removed.

| Path | Action |
|---|---|
| `CONTRIBUTING.md` | Rewritten — short stub saying personal fork, not open to external contributors, pointer to upstream |
| `SECURITY.md` | Rewritten — drops Sparkle/release-credential guidance (Sparkle disabled on this fork; upstream release scripts not safe to run) |
| `CODE_OF_CONDUCT.md` | Deleted — no community to govern |
| `.github/ISSUE_TEMPLATE/` | Deleted — bug-report / feature-request / contact-links templates; not relevant for a personal fork |
| `.github/PULL_REQUEST_TEMPLATE/` | Deleted — full and minimal PR templates; not relevant for a personal fork |
| `.github/workflows/brew-release.yml` | Deleted — pushed Homebrew cask updates to `the-ora/homebrew-ora`; doesn't apply here |
| `.github/CODEOWNERS` | Deleted — pointed at upstream Ora maintainers |
| `.github/FUNDING.yml` | Deleted — upstream funding config |
| `ROADMAP.md` | Already Evo-focused; Ora mentions retained are contextual attribution to the fork base, not stale branding |

## Carried but unused upstream artifacts

These remain in the repo for now because removing them is more divergence than benefit. If we never enable Sparkle, consider deleting in a later cleanup pass:

- `appcast.xml` — Ora's release feed
- `ora_public_key.pem` — Ora's Sparkle public key
- `scripts/build.sh`, `scripts/release.sh`, `scripts/publish.sh`, `scripts/_common.sh`, `scripts/generate-changelog.py`, `scripts/prompts/` — Ora's signed-release / DMG / notarization / changelog-generation pipeline. They reference `Ora.xcodeproj` (still our project name) and `com.orabrowser.app` (no longer our bundle ID), so they are **not safe to run as-is**. Re-brand or remove if/when we set up our own release pipeline.

## Pending fork decisions (not yet patched)

- **App icon assets** — `ora/Assets/Icons/OraIcon.icon` and `OraIconDev.icon` are Ora's logo. We're still shipping their icon. Replace before any external distribution. (Internal asset *names* stay as `OraIcon` / `OraIconDev` per the asset-catalog name pinning in `project.yml`.)
- **`.github/workflows/build-and-test.yml`** — upstream's lint-only CI. Leaving as-is — it only lints/resolves SPM, doesn't push or publish anything Ora-branded. If we want CI that actually builds and uploads `Evo.app`, that's a Phase-2 deliverable.
- **`OraColorLogo` image asset** — referenced in `OraRoot.swift` for the Quit-Evo confirmation dialog. Asset name stays internal; the actual image is still Ora-branded. Replace when icon assets are replaced.
- **Internal `Ora`-prefixed Swift identifiers** (e.g. `OraApp`, `OraCommands`, `OraRoot`, `OraButton`, `OraIcon`, `OraBrowserScripts`, `oraShortcut`, `oraDefault`, `OraTests`, `OraData`-keyed enum cases like `case ora`) — left untouched. Internal identifiers, never user-facing.
- **Xcode-generated file-header comments** (`//  ora` at the top of upstream-authored files) — left as-is. Harmless; would create huge diff noise to rewrite.
