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

## Carried but unused upstream artifacts

These remain in the repo for now because removing them is more divergence than benefit. If we never enable Sparkle, consider deleting in a later cleanup pass:

- `appcast.xml` — Ora's release feed
- `ora_public_key.pem` — Ora's Sparkle public key
- `scripts/build.sh`, `scripts/release.sh`, `scripts/publish.sh`, `scripts/_common.sh`, `scripts/generate-changelog.py`, `scripts/prompts/` — Ora's signed-release / DMG / notarization / changelog-generation pipeline. They reference `Ora.xcodeproj` (still our project name) and `com.orabrowser.app` (no longer our bundle ID), so they are **not safe to run as-is**. Re-brand or remove if/when we set up our own release pipeline.
- `.github/workflows/brew-release.yml` — pushes Homebrew cask updates to `the-ora/homebrew-ora`. Will not run on our fork unless we fork that repo too.

## Pending fork decisions (not yet patched)

- **App icon assets** — `ora/Assets/Icons/OraIcon.icon` and `OraIconDev.icon` are Ora's logo. We're still shipping their icon. Replace before any external distribution.
- **`.github/workflows/build-and-test.yml`** — upstream's lint-only CI. Leaving as-is. If we want CI that actually builds and uploads `Evo.app`, that's a Phase-2 deliverable.
- **README.md and ROADMAP.md** — partially rewritten in this fork. README is a fork patch (see git history). ROADMAP.md is upstream's; we'll likely replace with our own roadmap in Phase 2.
- **Visible "Ora" strings in Swift** (e.g. `OraApp`, `OraCommands`, `OraRoot`, log prefixes) — left untouched. Internal identifiers, never user-facing.
