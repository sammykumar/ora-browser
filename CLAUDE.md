# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Evo Browser — a personal, single-user Arc-replacement browser built on Swift + SwiftUI + WKWebView for macOS. Not intended for public release. Licensed under GPL-3.0 — see `LICENSE` and `README.md` for the required upstream attribution.

The differentiating feature is **AI-aware browsing with MCP integration** — connecting evo to local dev-project MCP servers and letting AI act on pages and local tools. This goes beyond simple "Ask Grok / Ask ChatGPT" entries, which are just URL shortcuts that pre-fill a query on those sites. Anthropic's Swift MCP SDK is the intended integration vehicle. Work that moves toward MCP / AI-agentic capability should be prioritized over polish on browsing features that already work.

## Project context

- **Solo dev, personal tool.** One user (Sam Kumar). Optimize for maintainability and "get it working" over enterprise patterns or feature breadth.
- **Paid Apple Developer account.** Full entitlements available when needed.
- **Primary platform: macOS.** iOS / iPadOS is a tractable future port (both use WKWebView); not an active priority. Aura Browser ([doorhinge-apps/Aura-Browser](https://github.com/doorhinge-apps/Aura-Browser)) is the reference for that path. Android / Windows / Linux are off the table — they were ruled out when choosing the codebase this project was built on.
- **No browser-level ad/tracker blocking needed.** User runs Pi-hole at DNS. Don't propose uBlock-equivalent work or new content-blocker features. The existing `AdBlockService` / SafariConverterLib wiring is inherited from upstream — leave it alone, don't extend it.
- **No extensions support needed initially.** `WKWebExtension` (macOS 15.4+) exists if it becomes wanted later; not a priority.
- User is comfortable learning Swift/SwiftUI but not yet deep in the broader Apple ecosystem — when introducing Apple-specific patterns (App Intents, CloudKit, etc.), briefly say what they are rather than assuming familiarity.

## Active priorities

Roughly:

1. **MCP client integration** via Anthropic's Swift MCP SDK — first connect to local dev-project MCP servers, then layer agentic page interaction on top.
2. **AI provider abstraction** — replace the hardcoded Grok / ChatGPT URL shortcuts with a proper provider layer that treats Anthropic Claude as a first-class option. (Worth scoping by first reading the existing command-bar / launcher code under `evo/Features/Launcher/` and `evo/Features/Search/` to find the abstraction seam.)

## Decisions already made — don't re-litigate

These were settled in planning. Don't reopen without strong new evidence:

| Chosen | Rejected | Why rejected |
|---|---|---|
| Build on an existing WKWebView-based Swift/SwiftUI codebase | Build from scratch using Aura as reference | Starting from working UI scaffolding saved ~3 months; speed-to-MCP matters more than architectural control for a personal tool |
| WebKit / WKWebView rendering | Chromium fork | Less efficient than WebKit on Mac; user prefers non-Chromium; overkill for personal use |
| WebKit / WKWebView rendering | Zen Browser fork (Gecko / Firefox chrome) | Extension ecosystem isn't needed (Pi-hole + native dev); no realistic mobile path (GeckoView Android vs. WebKit iOS); rebase pain against an upstream Gecko-based project |
| Native Swift / SwiftUI | Tauri 2 (Rust + web UI) | Loses the inherited UI head start; can't match native Mac materials/gestures; Apple ecosystem integration (Handoff, iCloud, App Intents) is painful in Tauri |

If you find yourself about to suggest "what if we rewrote this in X" or "have you considered switching to Y," check this table first.

## Commands

The project is XcodeGen-driven. `Evo.xcodeproj` is generated and gitignored.

```bash
# One-time / after editing project.yml
xcodegen

# Build (debug, unsigned) — primary local-dev path
./scripts/xcbuild-debug.sh
# → ~/Library/Developer/Xcode/DerivedData/Evo-*/Build/Products/Debug/Evo.app

# Run
open ~/Library/Developer/Xcode/DerivedData/Evo-*/Build/Products/Debug/Evo.app

# Tests (xcodebuild)
xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

# Single test (Xcode test identifier syntax: Target/Class/method)
xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  -only-testing:evoTests/EvoTests/testExample

# Lint / format (matches what lefthook would run pre-commit if enabled)
swiftformat .
swiftlint lint --use-alternative-excluding
swiftlint lint --fix --use-alternative-excluding
```

Force-quit the running app (e.g. when first-launch dialogs block `osascript quit`):

```bash
pkill -f "Evo.app/Contents/MacOS/Evo"
```

## Test layout

`evoTests/` is the only test target declared in `project.yml`. Test files `@testable import Evo` (matching the app module) and use the Swift Testing framework (`import Testing`); suites are plain `struct`s (`EvoTests`, `BrowserPageHostViewTests`), not `XCTestCase` subclasses.

## Source layout

All app source lives in `evo/`. High-level structure:

- `evo/App/` — `@main` entry point (`EvoApp`), `AppDelegate`, `EvoRoot` (the per-window scene root), `EvoCommands` (menu bar).
- `evo/Core/` — engine and cross-feature services.
  - `BrowserEngine/` — `BrowserEngine` (singleton) + per-`TabContainer` `BrowserEngineProfile`s wrapping `WKWebsiteDataStore`. `BrowserPage` is the WKWebView wrapper; `BrowserPageView` bridges it into SwiftUI.
  - `Services/App/` — singletons: `AppearanceManager`, `UpdateService` (Sparkle), `DefaultBrowserManager`, `CustomKeyboardShortcutManager`, `KeyModifierListener`.
  - `Extensions/ModelConfiguration+Shared.swift` — **single source of truth** for the SwiftData container. Schema is `[TabContainer, History, Download]`; private windows get an in-memory configuration.
- `evo/Features/` — feature folders (`Browser`, `Tabs`, `Sidebar`, `Launcher`, `Settings`, `History`, `Downloads`, `Search`, `FindInPage`, `Importer`, `Passwords`, `Player`, `Privacy`). Each typically has `Models/`, `State/` (the `ObservableObject` managers), and `Views/`.
- `evo/Shared/` — reusable UI primitives (`Components`, `Layout/SplitView` is vendored third-party code — see `THIRD_PARTY_NOTICES.md`, `Modifiers`, `Shapes`, `EmojiPicker`).
- `evo/Resources/WebScripts/` — JavaScript injected into pages via `BrowserUserScript`.
- `evo/Info/` — `Info.plist`, entitlements (`evo.entitlements`, `evo-debug.entitlements`).

## Architecture notes worth knowing before editing

**Multi-window scene model.** `EvoApp` declares three `WindowGroup`s: `normal`, `private`, and `settings`. Each non-settings window instantiates its own `EvoRoot`, which **constructs its own `ModelContext` and its own set of `@StateObject` managers** (`TabManager`, `HistoryManager`, `DownloadManager`, `SidebarManager`, etc.). Managers are per-window, not app-wide. Singletons (`BrowserEngine.shared`, `AppearanceManager.shared`, `AdBlockService.shared`, `ToastManager.shared`, `PrivacyService`, etc.) are the cross-window state.

**Private mode.** `EvoRoot(isPrivate: true)` swaps the SwiftData configuration to in-memory and tags tabs/profiles as private. `BrowserEngine.makeProfile(identifier:isPrivate:)` returns a non-cached `BrowserEngineProfile` for private containers so their `WKWebsiteDataStore` is non-persistent.

**WebKit profiles per `TabContainer`.** Containers (the app's term for "Spaces") each get a `BrowserEngineProfile` keyed by `(UUID, isPrivate)`. That's where cookies / cache / data partitioning lives — `PrivacyService.clearCacheForHost(container:)` and friends operate on a specific profile, not globally.

**Event bus via `NotificationCenter`.** `EvoRoot.onAppear` registers a large set of observers (`openURL`, `closeActiveTab`, `findInPage`, `toggleFullURL`, `reloadPage`, `clearCacheAndReload`, `spacePrivacySettingsChanged`, etc.). Each observer **filters by `note.object as? NSWindow === window`** so a notification only affects its source window. When adding a new global action, follow that pattern — drop the filter and you'll fire the action in every open window. Notification names are defined as `Notification.Name` extensions; grep for `extension Notification.Name` to find them.

**Menu commands → notifications.** `EvoCommands` posts notifications rather than calling managers directly (keeping menu handlers decoupled from per-window state). The matching observer in `EvoRoot` does the actual work.

**Hot reload (Inject).** `AppDelegate.applicationDidFinishLaunching` loads InjectionIII bundles in Debug. Views opt in with `@ObserveInjection var inject` + `.enableInjection()`. If `/Applications/InjectionIII.app` isn't installed, the app logs and proceeds normally — no functional impact.

**WKWebView script messages.** `BrowserPageConfiguration.evoDefault` declares the bridge: `["listener", "linkHover", "mediaEvent", "passwordManager"]`. Adding a new JS-to-Swift channel means registering the name here *and* handling it in `BrowserPageDelegate`.

## WKWebView capability reference

Useful when scoping features — what's confirmed available vs. not exposed (current as of macOS 15.4 / iOS 18.4):

**Available — build on these:**
- Remote Web Inspector debugging (macOS 13.3+).
- `WKWebExtension` — Safari Web Extension support (macOS 15.4+).
- Web Push, `WKDownload`, `WKURLSchemeHandler`, `WKContentRuleList`.
- Isolated-world JS injection via `evaluateJavaScript(in:contentWorld:)`.
- WebGPU, Passkeys / WebAuthn, Service Workers.
- Theme-color observation, find interactions, fullscreen API.

**Not exposed — bundle a library or use a system framework:**
- Reader Mode → bundle Mozilla `Readability.js`.
- On-page Apple Intelligence features → use the Anthropic API or the `FoundationModels` framework directly.
- Safari Translate → use the system `Translation` framework.
- iCloud Tabs / Bookmarks sync → build on CloudKit.
- Safari's private process-pool optimizations and native Tab Groups model — own data layer required (Evo already has one — see `TabContainer` / `BrowserEngineProfile`).

## Sparkle is disabled

`SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, and `SUEnableInstallerLauncherService` are stripped from `project.yml`. The Sparkle SPM dependency and `UpdateService` are still wired up, but `checkForUpdatesInBackground()` will not find an appcast — there is no publishing pipeline for this project. Don't reintroduce an appcast URL without also standing up a real release pipeline.

## Style

- SwiftFormat enforces 4-space indent, 120-col wrap, `--self remove`. See `.swiftformat`.
- SwiftLint opts in to `force_unwrapping` and `implicitly_unwrapped_optional` — avoid both in new code. See `.swiftlint.yml` for rule overrides.
- Lefthook hooks (swiftformat + swiftlint pre-commit, debug build pre-push) are **intentionally not installed**. Run the formatters manually before committing.
