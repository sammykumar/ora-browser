# BUILD.md

How to build and run this fork from a fresh clone. Verified 2026-05-09 on macOS 26.4.1 (arm64) with Xcode 26.4.1.

## Prerequisites

| Tool | Required | Confirmed |
|---|---|---|
| macOS | 15.0+ | 26.4.1 |
| Xcode (stable) | 15+ | 26.4.1 (Build 17E202) |
| Swift | 5.9 (language mode) | 6.3.1 compiler — backwards-compatible |
| Homebrew | any recent | 5.1.10 |

`project.yml` pins `SWIFT_VERSION: 5.9` — the Swift 6.x compiler that ships with current Xcode honors that mode.

## One-time setup

```bash
brew install xcodegen swiftlint swiftformat xcbeautify
xcodegen
```

`xcodegen` reads `project.yml` and writes `Evo.xcodeproj` (gitignored). Re-run it whenever `project.yml` changes.

> **Note on git hooks:** upstream's `./scripts/setup.sh` also installs `lefthook` git hooks (swiftformat + swiftlint pre-commit, debug build pre-push). This fork intentionally skips them. To opt back in later: `brew install lefthook && lefthook install`.

## Build (debug, unsigned)

```bash
./scripts/xcbuild-debug.sh
```

That wraps:

```bash
xcodebuild build -scheme evo -destination "platform=macOS" -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO | xcbeautify
```

Output bundle:

```
~/Library/Developer/Xcode/DerivedData/Evo-*/Build/Products/Debug/Evo.app
```

The build emits one expected warning — `evo isn't code signed but requires entitlements` — because `project.yml` declares sandbox / network / camera / microphone entitlements but unsigned binaries can't carry them. The app runs fine for local dev; entitlement-gated APIs (sandbox isolation, hardened runtime) are inert.

## Run

```bash
open ~/Library/Developer/Xcode/DerivedData/Evo-*/Build/Products/Debug/Evo.app
# or, with a URL:
open -a "<path-to-Evo.app>" "https://example.com"
```

## Test

```bash
xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

28 tests across 2 suites (`BrowserPageHostViewTests`, `OraTests`). Runs in ~0.1s. The xcresult bundle lands in DerivedData/Logs/Test.

## Quirks worth knowing

### Code-signing in `project.yml`

This fork patches Debug to `CODE_SIGN_STYLE: Automatic` and removes upstream's hard-coded team and provisioning profile (see `FORK_PATCHES.md`). Xcode GUI Run will use your personal Apple ID team automatically — you'll be prompted to select one the first time you build via Xcode. CLI builds via `./scripts/xcbuild-debug.sh` continue to bypass signing entirely.

Release config still has `CODE_SIGN_STYLE: Manual` and `CODE_SIGN_IDENTITY: Developer ID Application` from upstream, but the `DEVELOPMENT_TEAM` and `PROVISIONING_PROFILE_SPECIFIER` fields are blank. Signed Release builds will require you to provide your own team and profile (TBD).

### Hot-reload via Inject

`project.yml` includes the [Inject](https://github.com/krzysztofzablocki/Inject) SPM dependency and the Debug config sets `OTHER_LDFLAGS: "-Xlinker -interposable"`. At launch the app logs `Inject: InjectionIII bundle not found` if `/Applications/InjectionIII.app` isn't installed. Hot-reload is disabled in that case but the app behaves normally. Install [InjectionIII](https://github.com/johnno1962/InjectionIII) if you want live SwiftUI tweaking.

### Polite quit can be blocked

On first launch Evo shows a system-level dialog (likely "Set as default browser"). While that dialog is up, `osascript -e 'tell application "Evo" to quit'` returns `-128 user-cancelled` or `-1712 timeout`. Force-quit if needed:

```bash
pkill -f "Evo.app/Contents/MacOS/Evo"
```

### Signed/notarized release builds

`scripts/build.sh`, `scripts/release.sh`, `scripts/publish.sh` are upstream's full DMG / Sparkle pipeline. They require a `.env` (see `.env.example`) with `TEAM_ID`, `SIGNING_IDENTITY`, `DEVELOPER_ID_PROFILE`, `APP_SPECIFIC_PASSWORD_KEYCHAIN` and a Developer ID certificate in the keychain. Out of scope for local development.

### SPM dependencies

Resolved automatically by Xcode/`xcodebuild` from `project.yml`:

- Sparkle 2.6+ — auto-update framework
- Inject 1.5.2+ — SwiftUI hot reload (Debug only)
- FaviconFinder 5.1.5
- SafariConverterLib 4.2.2 — `ContentBlockerConverter` product

The `Vendor/SplitView/` directory holds only a `LICENSE` file — the actual SplitView source is vendored into `evo/Shared/Layout/SplitView/`.

## Reproducible one-liner

```bash
brew install xcodegen swiftlint swiftformat xcbeautify \
  && xcodegen \
  && ./scripts/xcbuild-debug.sh \
  && open ~/Library/Developer/Xcode/DerivedData/Evo-*/Build/Products/Debug/Evo.app
```
